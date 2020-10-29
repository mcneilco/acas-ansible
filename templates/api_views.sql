DROP VIEW IF EXISTS api_vial_log;
DROP MATERIALIZED VIEW IF EXISTS api_vial_log_mv;
DROP VIEW IF EXISTS api_vial_log_view;
DROP VIEW IF EXISTS api_aliquot_inventory;
DROP MATERIALIZED VIEW IF EXISTS api_aliquot_inventory_mv;
DROP VIEW IF EXISTS api_aliquot_inventory_view;
DROP VIEW IF EXISTS api_container_location_tree;
DROP VIEW IF EXISTS api_dose_response;
DROP MATERIALIZED VIEW IF EXISTS api_dose_response_mv;
DROP VIEW IF EXISTS api_analysis_group_results;
DROP MATERIALIZED VIEW IF EXISTS api_analysis_group_results_mv;
DROP VIEW IF EXISTS api_analysis_group_results_view;
DROP VIEW IF EXISTS p_api_analysis_group_results;
DROP VIEW IF EXISTS api_salt_form_assoc;
DROP MATERIALIZED VIEW IF EXISTS api_salt_form_assoc_mv;
DROP VIEW IF EXISTS api_salt_form;
DROP MATERIALIZED VIEW IF EXISTS api_salt_form_mv;
DROP MATERIALIZED VIEW IF EXISTS api_salt_form_corp_name;


DROP USER IF EXISTS readonly;
drop owned by readaccess;

-- Create a group
DROP ROLE IF EXISTS readaccess;
CREATE ROLE readaccess;

-- Grant access to existing tables
GRANT USAGE ON SCHEMA acas TO readaccess;
GRANT USAGE ON SCHEMA compound TO readaccess;
GRANT SELECT ON ALL TABLES IN SCHEMA compound TO readaccess;
GRANT SELECT ON ALL TABLES IN SCHEMA acas TO readaccess;
GRANT usage on schema bingo to readaccess;
GRANT select on all tables in schema bingo to readaccess;
GRANT execute on all functions in schema bingo to readaccess;

-- Grant access to future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA acas GRANT SELECT ON TABLES TO readaccess;
ALTER DEFAULT PRIVILEGES IN SCHEMA compound GRANT SELECT ON TABLES TO readaccess;

-- Create a final user with password
CREATE USER readonly WITH PASSWORD 'readonly';
GRANT readaccess TO readonly;

--Set search path
ALTER ROLE readonly SET search_path TO public,acas,compound;

SET SESSION AUTHORIZATION 'readonly';
set role readonly;
SET search_path TO public,acas,compound;

-- aliquot inventory


CREATE OR REPLACE VIEW api_container_location_tree AS
WITH RECURSIVE t1 ( 
    code_name, 
    parent_code_name, 
    label_text, 
    lvl, 
    root_code_name, 
    code_name_bread_crumb, 
    label_text_bread_crumb 
) AS ( 
  -- Anchor member. 
    SELECT 
        code_name, 
        CAST ( NULL AS text) AS parent_code_name, 
        label_text, 
        1 AS lvl, 
        code_name AS root_code_name, 
        CAST ( code_name AS text) AS code_name_bread_crumb, 
        CAST ( label_text AS text) AS label_text_bread_crumb, 
        ls_type, 
        ls_kind 
    FROM 
        (SELECT 
        c.code_name, 
        cl.label_text,  
        c.ls_type ,
        c.ls_kind  
    FROM 
        container c 
        JOIN container_label cl ON 
            c.id = cl.container_id 
        AND 
            cl.ignored = '0' 
        AND 
            cl.deleted = '0' 
    WHERE 
            c.deleted = '0'
        AND 
--root label, must be specified per customer
	            cl.label_text = 'Arvinas'
  ) as anchord 
    UNION ALL 
  -- Recursive member. 
     SELECT 
        interactions.code_name, 
        interactions.parent_code_name, 
        interactions.label_text, 
        lvl + 1, 
        t1.root_code_name, 
        t1.code_name_bread_crumb 
         || '>' 
         || interactions.code_name AS code_name_bread_crumb, 
        t1.label_text_bread_crumb 
         || '>' 
         || interactions.label_text AS label_text_bread_crumb, 
        interactions.ls_type,  
         interactions.ls_kind 
    FROM 
        (SELECT c1.code_name AS code_name, 
        cl1.label_text AS label_text, 
        c2.code_name AS parent_code_name, 
    	   c1.ls_type, 
    	   c1.ls_kind 
    FROM 
        itx_container_container itx 
        JOIN container c1 ON 
            itx.first_container_id = c1.id 
        AND 
            c1.ignored = '0' 
        AND 
            c1.deleted = '0' 
        JOIN container c2 ON 
            itx.second_container_id = c2.id 
        AND 
            c2.ignored = '0' 
        AND 
            c2.deleted = '0' 
        JOIN container_label cl1 ON 
            c1.id = cl1.container_id 
        AND 
            cl1.ignored = '0' 
        AND 
            cl1.deleted = '0' 
    WHERE 
            itx.ls_type = 'moved to' 
        AND 
            itx.ignored = '0' 
        AND 
            itx.deleted = '0') as interactions, 
        t1 
    WHERE 
        interactions.parent_code_name = t1.code_name 
) 
SELECT 
    code_name, 
    parent_code_name, 
    label_text, 
    rpad( 
        '.', 
        (lvl - 1) * 2, 
        '.' 
    ) 
     || code_name AS code_tree, 
    rpad( 
        '.', 
        (lvl - 1) * 2, 
        '.' 
    ) 
     || label_text AS label_tree, 
    lvl, 
    root_code_name, 
    code_name_bread_crumb, 
    label_text_bread_crumb, 
    ls_type, 
    ls_kind 
FROM 
    t1 ;
--------
CREATE OR REPLACE VIEW api_aliquot_inventory_view AS
SELECT tube.id AS id,
tube_barcode.label_text AS barcode,
tube.code_name AS tube_code,
batch_code_value.code_value AS batch_code,
physical_state_value.code_value AS physical_state,
parent_tube_barcode.label_text AS parent_vial,
tube_created_user_value.code_value AS created_user,
tube_created_date_value.date_value AS created_date,
tube.recorded_by AS recorded_by,
tube.recorded_date AS recorded_date,
initial_amount_value.numeric_value AS initial_amount,
initial_amount_value.unit_kind AS initial_amount_units,
amount_value.numeric_value AS amount,
amount_value.unit_kind AS amount_units,
batch_code_value.concentration AS batch_concentration,
batch_code_value.conc_unit AS batch_conc_units,
location_name_val.string_value AS location,
api_container_location_tree.parent_code_name AS location_code,
api_container_location_tree.label_text_bread_crumb AS location_bread_crumb,
solvent_value.code_value AS solvent,
vial_type_val.code_value AS vial_type,
comments_value.string_value AS comments
FROM container tube
JOIN container_label tube_barcode ON tube_barcode.container_id = tube.id AND tube_barcode.ls_type = 'barcode' AND tube_barcode.ls_kind = 'barcode' AND tube_barcode.ignored <> '1'
LEFT JOIN container_state tube_metadata_state ON tube.id = tube_metadata_state.container_id AND tube_metadata_state.ls_type = 'metadata' AND tube_metadata_state.ls_kind = 'information' AND tube_metadata_state.ignored <> '1'
LEFT JOIN container_value tube_created_user_value ON tube_metadata_state.id = tube_created_user_value.container_state_id AND tube_created_user_value.ls_type = 'codeValue' AND tube_created_user_value.ls_kind = 'created user' AND tube_created_user_value.ignored <> '1'
LEFT JOIN container_value tube_created_date_value ON tube_metadata_state.id = tube_created_date_value.container_state_id AND tube_created_date_value.ls_type = 'dateValue' AND tube_created_date_value.ls_kind = 'created date' AND tube_created_date_value.ignored <> '1'
LEFT JOIN container_value comments_value ON tube_metadata_state.id = comments_value.container_state_id AND comments_value.ls_type = 'stringValue' AND comments_value.ls_kind = 'comments' AND comments_value.ignored <> '1'
LEFT JOIN container_value vial_type_val ON tube_metadata_state.id = vial_type_val.container_state_id AND vial_type_val.ls_type = 'codeValue' AND vial_type_val.ls_kind = 'type' AND vial_type_val.ignored <> '1'
LEFT JOIN container_value location_name_val ON tube_metadata_state.id = location_name_val.container_state_id AND location_name_val.ls_type = 'stringValue' AND location_name_val.ls_kind = 'locationName' AND location_name_val.ignored <> '1'
LEFT JOIN itx_container_container tube_well_itx ON tube.id = tube_well_itx.first_container_id AND tube_well_itx.ls_type = 'has member' AND tube_well_itx.ls_kind = 'container_well' AND tube_well_itx.ignored <> '1'
LEFT JOIN container well ON well.id = tube_well_itx.second_container_id AND well.ls_type = 'well' AND well.ls_kind = 'default' AND well.ignored <> '1'
LEFT JOIN container_state well_state ON well.id = well_state.container_id AND well_state.ls_type = 'status' AND well_state.ls_kind = 'content' AND well_state.ignored <> '1'
LEFT JOIN container_value batch_code_value ON well_state.id = batch_code_value.container_state_id AND batch_code_value.ls_type = 'codeValue' AND batch_code_value.ls_kind = 'batch code' AND batch_code_value.ignored <> '1'
LEFT JOIN container_value physical_state_value ON well_state.id = physical_state_value.container_state_id AND physical_state_value.ls_type = 'codeValue' AND physical_state_value.ls_kind = 'physical state' AND physical_state_value.ignored <> '1'
LEFT JOIN container_value amount_value ON well_state.id = amount_value.container_state_id AND amount_value.ls_type = 'numericValue' AND amount_value.ls_kind = 'amount' AND amount_value.ignored <> '1'
LEFT JOIN container_value solvent_value ON well_state.id = solvent_value.container_state_id AND solvent_value.ls_type = 'codeValue' AND solvent_value.ls_kind = 'solvent code' AND solvent_value.ignored <> '1'
LEFT JOIN container_value initial_amount_value ON initial_amount_value.id = 
	(SELECT min(initial_amount.id) FROM container_state initial_state JOIN container_value initial_amount ON initial_state.id = initial_amount.container_state_id 
		WHERE initial_state.ls_type = 'status' AND initial_state.ls_kind = 'content'
		AND initial_amount.ls_type = 'numericValue' AND initial_amount.ls_kind = 'amount' AND initial_state.container_id = well.id)
LEFT JOIN itx_container_container parent_well_itx ON parent_well_itx.second_container_id = well.id AND parent_well_itx.ls_type = 'added to' AND parent_well_itx.ls_kind = 'well_well' AND parent_well_itx.ignored <> '1'
LEFT JOIN container parent_well ON parent_well.id = parent_well_itx.first_container_id AND parent_well.ls_type = 'well' AND parent_well.ls_kind = 'default' AND parent_well.ignored <> '1'
LEFT JOIN itx_container_container parent_tube_well_itx ON parent_well.id = parent_tube_well_itx.second_container_id AND parent_tube_well_itx.ls_type = 'has member' AND parent_tube_well_itx.ls_kind = 'container_well' AND parent_tube_well_itx.ignored <> '1'
LEFT JOIN container parent_tube ON parent_tube.id = parent_tube_well_itx.first_container_id AND parent_tube.ls_type = 'container' AND parent_tube.ls_kind = 'tube' AND parent_tube.ignored <> '1'
LEFT JOIN container_label parent_tube_barcode ON parent_tube_barcode.container_id = parent_tube.id AND parent_tube_barcode.ls_type = 'barcode' AND parent_tube_barcode.ls_kind = 'barcode' AND parent_tube_barcode.ignored <> '1'
LEFT JOIN api_container_location_tree ON api_container_location_tree.code_name = tube.code_name
WHERE tube.ls_type = 'container' AND tube.ls_kind = 'tube' AND tube.ignored <> '1';

-----------
--DROP MATERIALIZED VIEW api_aliquot_inventory_mv;
CREATE MATERIALIZED VIEW api_aliquot_inventory_mv
	AS SELECT * FROM api_aliquot_inventory_view;

CREATE UNIQUE INDEX api_aliquot_inventory_uniq_idx ON api_aliquot_inventory_mv (id);

CREATE OR REPLACE VIEW api_aliquot_inventory
	AS SELECT * FROM api_aliquot_inventory_mv;

----------
--DROP VIEW api_vial_log;
CREATE OR REPLACE VIEW api_vial_log_view AS
SELECT log_state.id AS id,
tube.id AS tube_id, 
tube.code_name AS tube_code_name,
log_state.recorded_by, 
log_state.recorded_date,
entry_type_val.code_value AS entry_type,
entry_val.clob_value AS entry
FROM container tube
JOIN container_state log_state ON log_state.container_id = tube.id AND log_state.ls_type = 'metadata' AND log_state.ls_kind = 'log' AND log_state.ignored <> '1'
JOIN container_value entry_type_val ON entry_type_val.container_state_id = log_state.id AND entry_type_val.ls_type = 'codeValue' AND entry_type_val.ls_kind = 'entry type' AND entry_type_val.ignored <> '1'
JOIN container_value entry_val ON entry_val.container_state_id = log_state.id AND entry_val.ls_type = 'clobValue' AND entry_val.ls_kind = 'entry' AND entry_val.ignored <> '1';

--DROP MATERIALIZED VIEW api_vial_log_mv;
CREATE MATERIALIZED VIEW api_vial_log_mv
	AS SELECT * FROM api_vial_log_view;

CREATE UNIQUE INDEX api_vial_log_uniq_idx ON api_vial_log_mv (id);

CREATE OR REPLACE VIEW api_vial_log
	AS SELECT * FROM api_vial_log_mv;

-- analysis group results
CREATE OR REPLACE VIEW p_api_analysis_group_results AS 
 SELECT ag.id AS ag_id,
    ag.code_name AS ag_code_name,
    eag.experiment_id,
    agv2.code_value AS tested_lot,
    agv2.concentration AS tested_conc,
        CASE
            WHEN agv4.numeric_value IS NOT NULL AND agv2.concentration IS NOT NULL THEN ((((agv2.conc_unit || ' and ') || agv4.numeric_value) || ' ') || agv4.unit_kind)
            WHEN agv4.numeric_value IS NOT NULL THEN ((agv4.numeric_value || ' ') || agv4.unit_kind)
            ELSE agv2.conc_unit
        END AS tested_conc_unit,
    agv.id AS agv_id,
    agv.ls_type,
        CASE
            WHEN agv.ls_type::text = 'inlineFileValue' THEN agv.ls_type_and_kind
            ELSE agv.ls_kind
        END AS ls_kind,
    agv.operator_kind,
        CASE
            WHEN agv.ls_kind ~~ '%curve id' THEN NULL
            ELSE agv.numeric_value
        END AS numeric_value,
    agv.uncertainty,
    agv.unit_kind,
        CASE
            WHEN agv.ls_type in ('fileValue', 'inlineFileValue') THEN replace(agv.file_value, ' ', '%20')
            WHEN agv.ls_type = 'urlValue' THEN ((((((('<A HREF="' || replace(agv.url_value, ' ', '%20')) || '">') || agv.comments) || ' (') || agv.url_value) || ')') || '</A>')
            WHEN agv.ls_type = 'dateValue' THEN to_char(agv.date_value, 'yyyy-mm-dd')
            WHEN agv.ls_type = 'codeValue' THEN agv.code_value
            ELSE COALESCE(agv.string_value, agv.clob_value, agv.comments)
        END AS string_value,
    agv.comments,
    agv.recorded_date::date AS recorded_date,
    agv.public_data,
    e.protocol_id
   FROM experiment e
     JOIN experiment_analysisgroup eag ON e.id = eag.experiment_id
     JOIN analysis_group ag ON eag.analysis_group_id = ag.id
     JOIN analysis_group_state ags ON ags.analysis_group_id = ag.id
     JOIN analysis_group_value agv ON agv.analysis_state_id = ags.id AND agv.ls_kind <> 'batch code' AND agv.ls_kind <> 'time'
     JOIN analysis_group_value agv2 ON agv2.analysis_state_id = ags.id AND agv2.ls_kind = 'batch code'
     LEFT JOIN analysis_group_value agv4 ON agv4.analysis_state_id = ags.id AND agv4.ls_kind = 'time'
  WHERE ag.ignored = false AND ags.ignored = false AND agv.ignored = false AND e.ignored = false;




CREATE OR REPLACE VIEW api_analysis_group_results_view AS 
 SELECT p_api_analysis_group_results.ag_id,
    p_api_analysis_group_results.ag_code_name,
    p_api_analysis_group_results.experiment_id,
    p_api_analysis_group_results.tested_lot,
    p_api_analysis_group_results.tested_conc,
    p_api_analysis_group_results.tested_conc_unit,
    p_api_analysis_group_results.agv_id,
    p_api_analysis_group_results.ls_type,
    p_api_analysis_group_results.ls_kind,
    p_api_analysis_group_results.operator_kind,
    p_api_analysis_group_results.numeric_value,
    p_api_analysis_group_results.uncertainty,
    p_api_analysis_group_results.unit_kind,
    p_api_analysis_group_results.string_value,
    p_api_analysis_group_results.comments,
    p_api_analysis_group_results.recorded_date,
    p_api_analysis_group_results.public_data,
    p_api_analysis_group_results.protocol_id
   FROM p_api_analysis_group_results
  WHERE p_api_analysis_group_results.public_data = true;

CREATE MATERIALIZED VIEW api_analysis_group_results_mv AS
SELECT * FROM api_analysis_group_results_view;

CREATE OR REPLACE VIEW api_analysis_group_results AS
SELECT * FROM api_analysis_group_results_mv;

CREATE INDEX api_agr_mv_tested_lot_idx ON api_analysis_group_results_mv (tested_lot);
CREATE INDEX api_agr_mv_ls_tk_idx ON api_analysis_group_results_mv (ls_type, ls_kind);
CREATE UNIQUE INDEX api_agr_mv_agv_id_uniq_idx ON api_analysis_group_results_mv (agv_id);
CREATE INDEX api_agr_mv_expt_id_idx ON api_analysis_group_results_mv (experiment_id);
CREATE INDEX api_agr_mv_prot_id_idx ON api_analysis_group_results_mv (protocol_id);

CREATE MATERIALIZED VIEW api_dose_response_mv AS
 SELECT * FROM api_dose_response;

 CREATE UNIQUE INDEX api_dose_resp_respsubjvalue_uniq_idx ON api_dose_response_mv (responsesubjectvalueid);
 CREATE INDEX api_dose_resp_curveval_idx ON api_dose_response_mv (curvevalueid);
 CREATE INDEX api_dose_resp_respkind_idx ON api_dose_response_mv (responsekind);
 
 CREATE OR REPLACE VIEW api_dose_response AS
 SELECT * FROM api_dose_response_mv;

--salt forms
--step 1: collect all salts on salt form, then group by salts and equivalents and generate new corp name

CREATE MATERIALIZED VIEW api_salt_form_corp_name AS
SELECT parent_id, corp_name || string_agg( salt_equiv, '' ORDER BY salt_equiv) as unique_salt_form_corp_name, id as salt_form_id
FROM (
SELECT parent.id as parent_id, parent.corp_name, salt_form.id, salt.abbrev || iso_salt.equivalents as salt_equiv
FROM salt_form
JOIN parent ON salt_form.parent = parent.id
LEFT JOIN iso_salt ON iso_salt.salt_form = salt_form.id
LEFT JOIN salt ON iso_salt.salt = salt.id) a
GROUP BY parent_id, id, corp_name
ORDER BY unique_salt_form_corp_name;

CREATE UNIQUE INDEX api_salt_form_corp_name_uniq ON api_salt_form_corp_name (salt_form_id);

--step 2: dedupe newly generated salt form corp names into api_salt_form view and generate an id
CREATE MATERIALIZED VIEW api_salt_form_mv AS
SELECT min(salt_form_id) as id, unique_salt_form_corp_name as corp_name, parent_id
FROM api_salt_form_corp_name
GROUP BY unique_salt_form_corp_name, parent_id;

CREATE UNIQUE INDEX api_salt_form_mv_uniq ON api_salt_form_mv (id);

CREATE OR REPLACE VIEW api_salt_form AS
SELECT * FROM api_salt_form_mv;

--step 3: generate join table between api_salt_form and salt_form
CREATE MATERIALIZED VIEW api_salt_form_assoc_mv AS
SELECT salt_form_id as id, id as api_salt_form_id, salt_form_id
FROM api_salt_form_corp_name
JOIN api_salt_form ON api_salt_form.corp_name = api_salt_form_corp_name.unique_salt_form_corp_name;

CREATE UNIQUE INDEX api_salt_form_assoc_mv_uniq ON api_salt_form_assoc_mv (id);

CREATE OR REPLACE VIEW api_salt_form_assoc AS
SELECT * FROM api_salt_form_assoc_mv;
