USE
[fhirdb]
GO
IF EXISTS(SELECT 1 FROM sys.procedures WHERE Name = 'sp_getBCSDataStatewise')
BEGIN 
	DROP PROCEDURE [dbo].[sp_getBCSDataStatewise]
END
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:      <Author, , Name>
-- Create Date: <Create Date, , >
-- Description: <Description, , >
-- =============================================
CREATE PROCEDURE sp_getBCSDataStatewise
(
    @vMeasurementPeriodStartDate DATE,
	@vMeasurementPeriodEndDate DATE
)
AS
BEGIN
WITH 
EncounterTypeExpanded (id, code)
AS
(
    SELECT
        id,
        JSON_VALUE(EncounterType.[type.coding],'$[0].code')
    FROM [fhir].[EncounterType] EncounterType     
),
BreastCancerScreeningEligiblePatients (PatientId, EncounterDate)
AS
(
    SELECT
        Patient.id AS PatientId,
        Encounter.[period.end] AS EncounterDate
    FROM
        [fhir].[Encounter] AS Encounter
    -- join with EncounterTypeExpanded for encounter codes
    INNER JOIN EncounterTypeExpanded
		ON Encounter.Id = EncounterTypeExpanded.id
    AND EncounterTypeExpanded.code IN ('86013001','185345009','3391000175108', '444971000124105', '439708006', '90526000')
    AND Encounter.[period.end] BETWEEN @vMeasurementPeriodStartDate AND @vMeasurementPeriodEndDate
    -- Join to the patient
    INNER JOIN [fhir].[Patient] as Patient         
        ON Patient.id = SUBSTRING([Encounter].[subject.reference], 9, 1000)
    WHERE
        Patient.gender = 'female'
        AND DATEDIFF(year, Patient.birthDate, @vMeasurementPeriodEndDate) >= 50
        AND DATEDIFF(year, Patient.birthDate, @vMeasurementPeriodEndDate) <= 70       
),
MammogramProcedure(id,PatientID,performedperiod)
AS
(
	SELECT 
		[pro].[id],
		[subject.reference] AS PatientID,
		[performed.period.end]
	FROM [fhir].[Procedure] AS [pro]
		CROSS APPLY openjson (pro.[code.coding]) WITH (
        [system]          VARCHAR(256)        '$.system',
        [code]            VARCHAR(256)        '$.code',
        [display]         VARCHAR(256)        '$.display'
		) proSystem
	WHERE proSystem.code IN ('241055006','24623002','71651007')   
),
BCSNumerator (PatientID, [State])
AS
(
	SELECT DISTINCT
		Patient.id AS PatientID,
		JSON_VALUE(Patient.[address],'$[0].state') [state]
    FROM [fhir].[Patient] AS Patient
    INNER JOIN MammogramProcedure MP ON
    Patient.id = SUBSTRING(MP.PatientID, 9, 1000)
    INNER JOIN BreastCancerScreeningEligiblePatients ON
    BreastCancerScreeningEligiblePatients.PatientId = Patient.Id 
    AND
    DATEDIFF(MONTH, CONVERT (DATETIMEOFFSET,MP.performedperiod,111), @vMeasurementPeriodEndDate) < = 48
),

StatewisePercentage ( [State], Percentages)
AS 
(
	SELECT 
		[state],
		CONVERT(DECIMAL(10,2),COUNT(*) * 100.0 / SUM(COUNT(*)) OVER()) AS [Percentage]
	FROM BCSNumerator
	GROUP BY [state]
)

	SELECT '0 - 20' AS [Percentages], [State]
		FROM StatewisePercentage 
		WHERE Percentages between 0 and 20
	UNION All
		SELECT '21 - 40' as [Percentages], [State]
		FROM StatewisePercentage 
		WHERE Percentages between 21 and 40
	UNION All
		SELECT '41 - 60' as [Percentages], [State]
		FROM StatewisePercentage 
		WHERE Percentages between 41 and 60
	UNION All
		SELECT '61 - 80' as [Percentages], [State]
		FROM StatewisePercentage 
		WHERE Percentages between 61 and 80
	UNION All
		SELECT '81 - 100' as [Percentages], [State]
		FROM StatewisePercentage 
		WHERE Percentages between 81 and 100

END
GO
