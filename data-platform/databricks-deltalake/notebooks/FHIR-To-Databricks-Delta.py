# Databricks notebook source
# MAGIC %md # FHIR Resources Live Table Pipeline
# MAGIC 
# MAGIC This notebook shows a more complete, multiple resource pipeline of Delta Lake with FHIR data from Azure Health Data Services.
# MAGIC 
# MAGIC To run this notebook, import it and attach it to a Spark cluster.

# COMMAND ----------

# MAGIC %md ## Prerequisites
# MAGIC We will need to connect the downstream Azure Datalake from FHIR to Datalake to Databricks for this notebook. Check out [this tutorial](https://docs.microsoft.com/azure/databricks/data/data-sources/azure/adls-gen2/azure-datalake-gen2-sp-access) for more information.
# MAGIC 
# MAGIC You will need to have:
# MAGIC - An Azure Key Vault linked to a Databricks Secret Scope called `sample-secrets`.
# MAGIC - A Secret in Key Vault named `adls-access-client-id` containing the service principal client id.
# MAGIC - A Secret in Key Vault named `adls-access-client-secret` containing the service principal client secret.
# MAGIC - A Secret in Key Vault named `adls-access-tenant-id` containing the service principal tenant id.
# MAGIC - A Secret in Key Vault named `adls-storage-account-name` containing the storage account name used by FHIR to Data Lake.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Setup For Delta Lake
# MAGIC First, we'll mount our Azure Data Lake that the FHIR to Data Lake function is exporting to at 5 minute intervals.

# COMMAND ----------

# DBTITLE 0,Mount FHIR to Data Lake Storage Account
storage_account_name = dbutils.secrets.get(scope="sample-secrets", key="adls-storage-account-name")
storage_container_name = dbutils.secrets.get(scope="sample-secrets", key="adls-storage-container-name")
storage_account_key = dbutils.secrets.get(scope="sample-secrets", key="adls-access-account-key")
storage_account_path = f"abfss://{storage_container_name}@{storage_account_name}.dfs.core.windows.net"
spark.conf.set(
    f"fs.azure.account.key.{storage_account_name}.dfs.core.windows.net",
    storage_account_key
)

# COMMAND ----------

# MAGIC %md ## Schema Helper
# MAGIC 
# MAGIC Since Delta Live Tables don't support inferring parquet schemas, we need a helped to load these.

# COMMAND ----------

from pyspark.sql.types import StructType

def get_resource_schema(resource_name: str) -> StructType:
    df = spark.read.option("header","true").option("recursiveFileLookup","true").parquet(f"{storage_account_path}/result/{resource_name}")
    return df.schema

# COMMAND ----------

# MAGIC %md
# MAGIC ## Create Bronze Resource Tables
# MAGIC 
# MAGIC The Bronze layer is where we land all the data from external source systems. The table structures in this layer correspond to the source system table structures "as-is," along with any additional metadata columns that capture the load date/time, process ID, etc. The focus in this layer is quick Change Data Capture and the ability to provide an historical archive of source (cold storage), data lineage, auditability, reprocessing if needed without rereading the data from the source system.
# MAGIC 
# MAGIC We are ensuring Patients have identifiers as our only filter.

# COMMAND ----------

# DBTITLE 0,Create Patient Stream from FHIR to Data Lake
import dlt

raw_data_location = f"{storage_account_path}/result/"

@dlt.table(
  name="Patient_Raw",
  comment="Raw table for patients from FHIR",
  table_properties={
    "quality": "bronze"
  }
)
def get_raw_patients():
  return (
    spark
      .readStream
      .format("cloudFiles")
      .schema(get_resource_schema('Patient'))
      .option("cloudFiles.format", "parquet")
      .option("cloudFiles.includeExistingFiles", True)
      .load(raw_data_location + 'Patient')
  )

@dlt.table(
  name="Encounter_Raw",
  comment="Raw table for encounters from FHIR",
  table_properties={
    "quality": "bronze"
  }
)
def get_raw_encounters():
  return (
    spark
      .readStream
      .format("cloudFiles")
      .schema(get_resource_schema('Encounter'))
      .option("cloudFiles.format", "parquet")
      .option("cloudFiles.includeExistingFiles", True)
      .load(raw_data_location + 'Encounter')
  )
  
@dlt.table(
  name="Observation_Raw",
  comment="Raw table for observation from FHIR",
  table_properties={
    "quality": "bronze"
  }
)
def get_raw_observations():
  return (
    spark
      .readStream
      .format("cloudFiles")
      .schema(get_resource_schema('Observation'))
      .option("cloudFiles.format", "parquet")
      .option("cloudFiles.includeExistingFiles", True)
      .load(raw_data_location + 'Observation')
  )

# COMMAND ----------

# MAGIC %md
# MAGIC 
# MAGIC ## Silver: Cleaning and Filtering Scripts for Silver
# MAGIC 
# MAGIC In the Silver layer of the lakehouse, the data from the Bronze layer is matched, merged, conformed and cleansed ("just-enough") so that the Silver layer can provide an "Enterprise view" of all its key business entities, concepts and transactions. (e.g. master customers, stores, non-duplicated transactions and cross-reference tables).
# MAGIC 
# MAGIC Here, we are flattening our FHIR data to a more tabular format that matches our enterprise schema.
# MAGIC 
# MAGIC In a production deployment, this code should be extracted into a library that can be unit tested.

# COMMAND ----------

from pyspark.sql import DataFrame, Column
import pyspark.sql.functions as F

#################################
# HELPER FUNCTIONS
#################################

def first_identifier_value_by_system(system : str) -> Column:
    return F.filter('identifier', lambda x: x['system'] == system)[0]['value']

def first_official_name() -> Column:
    return F.transform(
        F.filter('name', lambda x: x['use'] == 'official'),
        lambda x: x.withField('first_name', x['given'][0]).withField('last_name', x['family'])
    )[0]

def first_phome_by_use(use : str) -> Column:
    return F.filter('telecom', lambda x: ((x['system'] == 'phone') & (x['use'] == use)))[0]['value']

def email_value() -> Column:
    return F.transform(F.filter('telecom', lambda x: x['system'] == 'email'), lambda x: x.value)[0]

def resource_id_from_path(resource_type: str, path: str) -> Column:
    return F.expr(f'if(substr({path}, 1, {len(resource_type) + 1}) == "{resource_type}/", substr({path}, {len(resource_type) + 2}), null)')

#################################
# Patient cleaning logic
#################################

def clean_patient_df(df : DataFrame) -> DataFrame:
    return (df
        .withColumn('synthea_identifier', first_identifier_value_by_system('https://github.com/synthetichealth/synthea'))
        .withColumn('official_name', first_official_name())
        .withColumn('home_phone', first_phome_by_use('home'))
        .withColumn('mobile_phone', first_phome_by_use('mobile'))
        .withColumn('email', email_value())
        .withColumn('first_address', F.col('address')[0])
        .withColumn('deceased_bool', F.expr('deceased.boolean is not null OR deceased.dateTime is not null as deceased'))
        .selectExpr(
            'resourceType',
            'id',
            'meta.versionId',
            'meta.lastUpdated',
            'synthea_identifier',
            'official_name',
            'official_name.first_name',
            'official_name.last_name',
            'home_phone',
            'mobile_phone',
            'email',
            'gender',
            'birthDate',
            'first_address',
            'first_address.line[0] as address_line_1',
            'first_address.line[1] as address_line_2',
            'first_address.line[2] as address_line_3',
            'first_address.city as address_city',
            'first_address.state as address_state',
            'first_address.postalCode as address_zip',
            'maritalStatus.coding[0].code as marital_status',
            'deceased_bool as deceased',
            'deceased.dateTime'
        )
    )

#################################
# Encounter cleaning logic
#################################

def clean_encounter_df(df : DataFrame) -> DataFrame:
    return (df
        .withColumn('synthea_identifier', first_identifier_value_by_system('https://github.com/synthetichealth/synthea'))
        .withColumn('patient_id', resource_id_from_path('Patient', 'subject.reference'))
        .selectExpr(
            'resourceType',
            'id',
            'meta.versionId',
            'meta.lastUpdated',
            'synthea_identifier',
            'class.code as class',
            'type[0].coding[0].code as type',
            'patient_id',
            'participant[0].individual.reference as practitioner',
            'period.start as start_date_time',
            'period.end as end_date_time'
        )
    )
    
#################################
# Observation cleaning logic
#################################

def extract_codes(column_name: str) -> Column:
    return F.transform(
        F.col(column_name)['coding'],
        lambda x: x.dropFields('id', 'extension', 'system', 'version', 'userSelected')
    )

def extract_codes_with_system(column_name: str, system: str) -> Column:
    return F.transform(
        F.filter(F.col(column_name)['coding'], lambda x: x['system'] == system),
        #lambda x: x.selectExpr('code', 'display', 'system')
        lambda x: x.dropFields('id', 'extension', 'system', 'version', 'userSelected')
    )
    
def extract_observation_values() -> Column:
    return F.coalesce(
        F.transform(F.col('component'), lambda x: x['value']['quantity']),
        F.array(F.col('value')['quantity'])
    )

def clean_observation_df(df : DataFrame) -> DataFrame:
    return (df
        .withColumn('extracted_codes', extract_codes_with_system('code', 'http://loinc.org'))
        .withColumn('patient_id', resource_id_from_path('Patient', 'subject.reference'))
        .withColumn('encounter_id', resource_id_from_path('Encounter', 'encounter.reference'))
        .withColumn('value_quantity', extract_observation_values())
        .withColumn('value_code', extract_codes('value.codeableConcept'))
        .selectExpr(
            'resourceType',
            'id',
            'meta.versionId',
            'meta.lastUpdated',
            'status',
            'category[0].coding[0].code as category',
            'extracted_codes',
            'patient_id',
            'encounter_id',
            'issued',
            'value_quantity',
            'value_code'
        )
    )

# Uncomment to test outside of delta live tables in this notebook
#clean_patient_df(spark.table("fhir.patient_raw")).display()
#clean_encounter_df(spark.table("fhir.encounter_raw")).display()
#clean_observation_df(spark.table("fhir.observation_raw")).display()

# COMMAND ----------

# MAGIC %md ## Create Silver Resource Tables
# MAGIC 
# MAGIC Here, we are taking our cleansing views and creating Silver tables. These tables will have only one row per record using the `key` and `sequency_by` parameters of `dlt.apply_changes`.

# COMMAND ----------

from pyspark.sql.functions import col, expr

@dlt.view(
  name="Patient_Bronze_Cleaned",
  comment="Cleansed bronze patient view (i.e. what will become Silver)"
)

@dlt.expect_or_drop("has record id", "id IS NOT NULL")
@dlt.expect_or_drop("has synthea identifier", "synthea_identifier IS NOT NULL")
@dlt.expect_or_drop("has official_name", "official_name IS NOT NULL")
@dlt.expect_or_drop("has address", "first_address IS NOT NULL")

def patient_bronze_cleaned():
    return clean_patient_df(dlt.read_stream("Patient_Raw"))

dlt.create_target_table(
  name="Patient_Cleaned",
  comment="De-duplicated and flattened patient data.",
  table_properties={
    "quality": "silver"
  }
)

dlt.apply_changes(
  target = "Patient_Cleaned",
  source = "Patient_Bronze_Cleaned",
  keys = ["id"],
  sequence_by = col("lastUpdated")
)

@dlt.view(
  name="Encounter_Bronze_Cleaned",
  comment="Cleansed bronze encounter view (i.e. what will become Silver)"
)

@dlt.expect_or_drop("has record id", "id IS NOT NULL")
@dlt.expect_or_drop("has synthea identifier", "synthea_identifier IS NOT NULL")
@dlt.expect_or_drop("has patient", "patient_id IS NOT NULL")
@dlt.expect_or_drop("has practitioner", "practitioner IS NOT NULL")
@dlt.expect_or_drop("has start_date", "start_date_time IS NOT NULL")

def encounter_bronze_cleaned():
    return clean_encounter_df(dlt.read_stream("Encounter_Raw"))

dlt.create_target_table(
  name="Encounter_Cleaned",
  comment="De-duplicated and flattened encounter data.",
  table_properties={
    "quality": "silver"
  }
)

dlt.apply_changes(
  target = "Encounter_Cleaned",
  source = "Encounter_Bronze_Cleaned",
  keys = ["id"],
  sequence_by = col("lastUpdated")
)

@dlt.view(
  name="Observation_Bronze_Cleaned",
  comment="Cleansed bronze observation view (i.e. what will become Silver)"
)

@dlt.expect_or_drop("has record id", "id IS NOT NULL")
@dlt.expect_or_drop("has patient", "patient_id IS NOT NULL")
@dlt.expect_or_drop("has encounter", "encounter_id IS NOT NULL")
@dlt.expect_or_drop("has issued", "issued IS NOT NULL")
@dlt.expect_or_drop("is final", "status == 'final'")
@dlt.expect_or_drop("has quantity or code", "value_quantity IS NOT NULL OR value_code IS NOT NULL")

def observation_bronze_cleaned():
    return clean_observation_df(dlt.read_stream("Observation_Raw"))

dlt.create_target_table(
  name="Observation_Cleaned",
  comment="De-duplicated, flattened, and cleaned observation data.",
  table_properties={
    "quality": "silver"
  }
)

dlt.apply_changes(
  target = "Observation_Cleaned",
  source = "Observation_Bronze_Cleaned",
  keys = ["id"],
  sequence_by = col("lastUpdated")
)

# COMMAND ----------

# MAGIC %md ## Create Gold Aggregate Table
# MAGIC 
# MAGIC Here is an example of creating a gold level aggregate table that is compatible with a streaming Delta Live Table. To enable streaming, [watermarks](https://databricks.com/blog/2017/05/08/event-time-aggregation-watermarking-apache-sparks-structured-streaming.html) are required so aggregates can be addedd to without a complete recalculation of the table.
# MAGIC 
# MAGIC It's recommended to recreate the entire table periodically (weekly, monthly, etc) to catch any events that have been missed.

# COMMAND ----------

import pyspark.sql.functions as F
from pyspark.sql.types import TimestampType
from pyspark.sql import DataFrame, window

def create_height_patient_observation_df(patientDf: DataFrame, observationDf: DataFrame):
    observationFilteredDf = observationDf \
        .filter(F.size(F.filter(F.col('extracted_codes'), lambda x: x['code'] == '8302-2')) == 1)
    joinedDf = (
        observationFilteredDf
            .join(other=patientDf, on=patientDf.id == observationDf.patient_id, how='inner')
    ) \
    .withColumn('timestamp', observationFilteredDf['lastUpdated'].cast(TimestampType())) \
    .withColumn('height', F.transform(F.col('value_quantity'), lambda x: x.value)[0]) \
    .withColumn('age', F.expr('int(months_between(issued, birthDate) / 12)')) \
    .withColumn('patient_city', patientDf['address_city']) \
    .selectExpr(
        'timestamp',
        'int(height / 10) * 10 as height_range',
        'int(age / 10) * 10 as age_range',
        'patient_city'
    ) \
    .withWatermark("timestamp", "15 minutes") \
    .groupBy(
            F.window(F.col('timestamp'), "15 minutes"),
            'age_range',
            'height_range',
            'patient_city'
    ) \
    .count()

    return joinedDf

# Test outside of delta live tables
#create_height_patient_observation_df(
#    spark.table("fhir.patient_cleaned"), 
#    spark.table("fhir.observation_cleaned")
#).display()

@dlt.create_table(
  comment="Height gold Observation/Encounter/Patient gold table.",
  table_properties={
    "quality": "gold"
  }    
)
def height_patient_encounter_observation():
    return create_height_patient_observation_df(dlt.read_stream("Patient_Cleaned"), dlt.read_stream("Observation_Cleaned"))

# COMMAND ----------

# MAGIC %md ## Cleanup
# MAGIC 
# MAGIC Once you're done testing, you can uncomment the code below to cleanup your testing environment.

# COMMAND ----------

'''
spark.sql("DROP TABLE IF EXISTS patient_cleaned")
spark.sql("DROP TABLE IF EXISTS patient_raw")
spark.sql("DROP TABLE IF EXISTS encounter_raw")

dbutils.fs.rm("/mnt/fhir/delta", True)
'''
