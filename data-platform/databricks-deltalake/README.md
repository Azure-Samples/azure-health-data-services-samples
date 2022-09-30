# FHIR Service Analytics with Azure Databricks Delta Lake Analytics

## Overview

Data Lakehouse is an open data architecture that combines existing features from traditional data lakes and data warehouses. Delta Lake has emerged as the leading storage framework that enables building a Lakehouse architecture on top of existing data lake technologies. Azure Health Data Services enables Lakehouse architectures by exporting parquet files of FHIR data which align to the open [SQL on FHIR](https://github.com/FHIR/sql-on-fhir/blob/master/sql-on-fhir.md) standard.

Building a Lakehouse for FHIR data has these advantages:

- Combining your FHIR data with other datasets.
- Having a consistent location of enterprise ready data enabling more self-service across your organization.
- Metadata management and versioning of data simplifing data that is often updated.

## Scenario Overview

For this sample, we will be building a simple Lakehouse exploring a single use case: a hospital admission report. Here, we've been asked to provide some simple data to enable trend analysis for hospital admissions. We'll only focus on Patient, Encounter, and Observation information, but the same approach can be expanded for other entities.

## Deploy the sample

Click the button below to launch Azure and deploy your sample. Open it in a new tab so you can keep referencing this readme.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fahdssampledata.blob.core.windows.net%2Ftemplates%2Fdata-platform%2Fdatabricks-deltalake%2Fazuredeploy.json)

## Looking around at what we deployed

This sample will deploy the following components:

- Azure Health Data Services Workspace
- FHIR Service
- Azure Data Lake Storage Gen 2
- Azure Databricks
- Azure Function with [FHIR to Data Lake Pipeline](https://github.com/microsoft/FHIR-Analytics-Pipelines/tree/main/FhirToDataLake)
- Managed identity for deployment scripts
- Role assignments
- Script to setup Azure Databricks with the sample
- Script to load sample data into the FHIR Service from Synthea


## Watch data flow through the sample

To test out this sample, launch the Azure Databricks workspace you just deployed. Go to the Delta Live Tables area of Azure Databricks and start the pipeline there.

#TODO - add screenshot.

## Explain the sample

This sample touches on one small, core area that you would need to repeat for other entities in your data. The core concepts are:

### Delta Live Tables with Auto Loader

Delta Live tables enable you to easily create a Delta Lake with your data from the FHIR Service. Schema is mostly handled for you and using Delta Live Tables with Auto Loader takes most of the complexity of creating your Delta Lake.

### Bronze Layer

For FHIR data from FHIR to Data Lake, the bronze layer is a copy of this data extracted from the Data Lake path exported from your FHIR service. Once this data is moved successfully to bronze and you are confident in your Delta Lake deployment, you can begin to delete the data in this Data Lake path once it is moved to bronze. The bronze layer should be as close to the format of your source systems as possible.

### Silver Layer

The silver layer is a collection of entity based tables that are transformed into core tables that apply across your business. We recommend that you flatten the data in these tables as much as you can to simplify connecting downstream applications directly to your silver layer (like PowerBI). FHIR data is heavily nested and it's best to incur the complexity of this transformation once in your data platform. More than flattening, your silver layer should have data elements that map to your business entities. For example, you may have column for your EMPI (enterprise master patient id) that is a flattened, filtered result from the identifier element on the patient resource.

### Gold Layer

Finally, the gold layer should house application specific aggregates of data. These tables are generally created per each application or application group and are targeted specifically at those. Applications can also pull data from the silver layer when it makes sense, but if this logic gets too complex or you are computing aggregates, a gold level table may be right for the scenario. Generally the gold layer data has a loss of record level fidelity from the silver layer.

## Using this in your own environment

To use this sample in your own production environment, we recommend that you look into Databricks best practices, especially around testing your code, extracing common functionality, CI/CD, monitoring, and alerting. For more details, please check out the links below.

- https://github.com/Azure/AzureDatabricksBestPractices/blob/master/toc.md
- https://github.com/Azure-Samples/modern-data-warehouse-dataops/tree/main/single_tech_samples/databricks/sample2_enterprise_azure_databricks_environment