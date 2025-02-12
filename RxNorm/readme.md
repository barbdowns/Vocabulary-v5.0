Update of RxNorm

Prerequisites:
- Schema DevV5 with copies of tables concept, concept_relationship and concept_synonym from ProdV5, fully indexed.
- SNOMED must be loaded first
- Working directory RxNorm.

1. Run create_source_tables.sql (and optional QA-script qa_rxnorm.sql)
2. Run FillDrugStrengthStage.sql in your dev-schema for RxNorm e.g. dev_rxnorm (this will create one procedure)
3. Download RxNorm_full_MMDDYYYY.zip from http://www.nlm.nih.gov/research/umls/rxnorm/docs/rxnormfiles.html
4. Extract files from the folder "rrf":
RXNATOMARCHIVE.RRF
RXNCONSO.RRF
RXNREL.RRF
RXNSAT.RRF

5. Run in devv5 (with fresh vocabulary date and version): SELECT sources.load_input_tables('RxNorm',TO_DATE('20180507','YYYYMMDD'),'RxNorm Full 20180507');
6. Run load_stage.sql
7. Run generic_update: devv5.GenericUpdate();

NOTE: When RxNorm is run in dev_rxnorm schema, rxn_info_sheet table is created.
Please review it's results, before running RxNorm in devv5