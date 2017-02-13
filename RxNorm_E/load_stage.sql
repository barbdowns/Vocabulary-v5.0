/**************************************************************************
* Copyright 2016 Observational Health Data Sciences and Informatics (OHDSI)
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
* 
* Authors: Timur Vakhitov, Christian Reich
* Date: 2016
**************************************************************************/

--1 Update latest_update field to new date 
BEGIN
   DEVV5.VOCABULARY_PACK.SetLatestUpdate (pVocabularyName        => 'RxNorm Extension',
                                          pVocabularyDate        => TRUNC(SYSDATE),
                                          pVocabularyVersion     => 'RxNorm Extension '||SYSDATE,
                                          pVocabularyDevSchema   => 'DEV_RXE');									  
END;
COMMIT;

--2 Truncate all working tables
TRUNCATE TABLE concept_stage;
TRUNCATE TABLE concept_relationship_stage;
TRUNCATE TABLE concept_synonym_stage;
TRUNCATE TABLE pack_content_stage;
TRUNCATE TABLE drug_strength_stage;

--3 Load full list of RxNorm Extension concepts
INSERT /*+ APPEND */ INTO  CONCEPT_STAGE (concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT concept_name,
          domain_id,
          vocabulary_id,
          concept_class_id,
          standard_concept,
          concept_code,
          valid_start_date,
          valid_end_date,
          invalid_reason
     FROM concept
    WHERE vocabulary_id = 'RxNorm Extension';			   
COMMIT;


--4 Load full list of RxNorm Extension relationships
INSERT /*+ APPEND */ INTO  concept_relationship_stage (concept_code_1,
                                        concept_code_2,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        relationship_id,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT c1.concept_code,
          c2.concept_code,
          c1.vocabulary_id,
          c2.vocabulary_id,
          r.relationship_id,
          r.valid_start_date,
          r.valid_end_date,
          r.invalid_reason
     FROM concept c1, concept c2, concept_relationship r
    WHERE c1.concept_id = r.concept_id_1 AND c2.concept_id = r.concept_id_2 AND 'RxNorm Extension' IN (c1.vocabulary_id, c2.vocabulary_id);
COMMIT;


--5 Load full list of RxNorm Extension drug strength
INSERT /*+ APPEND */
      INTO  drug_strength_stage (drug_concept_code,
                                 vocabulary_id_1,
                                 ingredient_concept_code,
                                 vocabulary_id_2,
                                 amount_value,
                                 amount_unit_concept_id,
                                 numerator_value,
                                 numerator_unit_concept_id,
                                 denominator_value,
                                 denominator_unit_concept_id,
                                 valid_start_date,
                                 valid_end_date,
                                 invalid_reason)
   SELECT c.concept_code,
          c.vocabulary_id,
          c2.concept_code,
          c2.vocabulary_id,
          amount_value,
          amount_unit_concept_id,
          numerator_value,
          numerator_unit_concept_id,
          denominator_value,
          denominator_unit_concept_id,
          ds.valid_start_date,
          ds.valid_end_date,
          ds.invalid_reason
     FROM concept c
          JOIN drug_strength ds ON ds.DRUG_CONCEPT_ID = c.CONCEPT_ID
          JOIN concept c2 ON ds.INGREDIENT_CONCEPT_ID = c2.CONCEPT_ID
    WHERE c.vocabulary_id IN ('RxNorm', 'RxNorm Extension');
COMMIT;

--6 Load full list of RxNorm Extension pack content
INSERT /*+ APPEND */
      INTO  pack_content_stage (pack_concept_code,
                                pack_vocabulary_id,
                                drug_concept_code,
                                drug_vocabulary_id,
                                amount,
                                box_size)
   SELECT c.concept_code,
          c.vocabulary_id,
          c2.concept_code,
          c2.vocabulary_id,
          amount,
          box_size
     FROM pack_content pc
          JOIN concept c ON pc.PACK_CONCEPT_ID = c.CONCEPT_ID
          JOIN concept c2 ON pc.DRUG_CONCEPT_ID = c2.CONCEPT_ID;
COMMIT;

--7
--do a rounding amount_value, numerator_value and denominator_value
update drug_strength_stage set 
    amount_value=round(amount_value, 3-floor(log(10, amount_value))-1),
    numerator_value=round(numerator_value, 3-floor(log(10, numerator_value))-1),
    denominator_value=round(denominator_value, 3-floor(log(10, denominator_value))-1)
where amount_value<>round(amount_value, 3-floor(log(10, amount_value))-1)
or numerator_value<>round(numerator_value, 3-floor(log(10, numerator_value))-1)
or denominator_value<>round(denominator_value, 3-floor(log(10, denominator_value))-1);
commit;

--8 
--wrong ancestor
update concept_stage set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
WHERE concept_code in (select an.concept_code from concept an
join concept_ancestor a on a.ancestor_concept_id=an.concept_id and an.vocabulary_id='RxNorm Extension'
join concept de on de.concept_id=a.descendant_concept_id and de.vocabulary_id='RxNorm')
and invalid_reason is null;
commit;

--9 
--impossible dosages
update concept_stage set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension')
where (concept_code,vocabulary_id) in (
select drug_concept_code, vocabulary_id_1 from drug_strength_stage a 
where (numerator_unit_concept_id=8554 and denominator_unit_concept_id is not null) 
or amount_unit_concept_id=8554
or ( numerator_unit_concept_id=8576 and denominator_unit_concept_id=8587 and numerator_value / denominator_value > 1000 )
or (numerator_unit_concept_id=8576 and denominator_unit_concept_id=8576 and numerator_value / denominator_value > 1 )
and vocabulary_id_1='RxNorm Extension')
and invalid_reason is null;
commit;

--10 
--wrong pack components
update concept_stage  set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension')
where (concept_code, vocabulary_id) in (
select pack_concept_code, pack_vocabulary_id  from pack_content_stage where pack_vocabulary_id='RxNorm Extension' group by drug_concept_code, drug_vocabulary_id, pack_concept_code, pack_vocabulary_id having count (*) > 1 )
and invalid_reason is null;
commit;

--11
--deprecate drugs that have different number of ingredients in ancestor and drug_strength
update concept_stage set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (concept_code, vocabulary_id) in (
    with a as (
        select drug_concept_code, vocabulary_id_1, count(drug_concept_code) as cnt1 
        from drug_strength_stage
        where vocabulary_id_1='RxNorm Extension'
        group by drug_concept_code, vocabulary_id_1
    ),
    b as (
        select b2.concept_code as descendant_concept_code, b2.vocabulary_id as descendant_vocabulary_id, count(b2.concept_code) as cnt2 
        from concept_ancestor a 
        join concept b on ancestor_concept_id=b.concept_id and concept_class_id='Ingredient'
        join concept b2 on descendant_concept_id=b2.concept_id 
        where b2.concept_class_id not like '%Comp%'
        and b2.vocabulary_id='RxNorm Extension'
        group by b2.concept_code, b2.vocabulary_id
    )
    select a.drug_concept_code, a.vocabulary_id_1
    from a 
    join b on a.drug_concept_code=b.descendant_concept_code and a.vocabulary_id_1=b.descendant_vocabulary_id
    where cnt1<cnt2
)
and invalid_reason is null;
commit;

update concept_stage set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (concept_code, vocabulary_id) in (
    with a as (
        select drug_concept_code, vocabulary_id_1, count(drug_concept_code) as cnt1 
        from drug_strength_stage
        where vocabulary_id_1='RxNorm Extension'
        group by drug_concept_code, vocabulary_id_1
    ),
    b as (
        select b2.concept_code as descendant_concept_code, b2.vocabulary_id as descendant_vocabulary_id, count(b2.concept_code) as cnt2  
        from concept_ancestor a 
        join concept b on ancestor_concept_id=b.concept_id and concept_class_id='Ingredient'
        join concept b2 on descendant_concept_id=b2.concept_id where b2.concept_class_id not like '%Comp%'
        and b2.vocabulary_id='RxNorm Extension'
        group by b2.concept_code, b2.vocabulary_id
    ),
    c as (
        select concept_code, vocabulary_id, regexp_count(concept_name,'\s/\s')+1 as cnt3 
        from concept
        where vocabulary_id='RxNorm Extension'
    )
    select a.drug_concept_code, a.vocabulary_id_1
    from a join b on a.drug_concept_code=b.descendant_concept_code and a.vocabulary_id_1=b.descendant_vocabulary_id
    join  c on c.concept_code=b.descendant_concept_code and c.vocabulary_id=b.descendant_vocabulary_id
    where cnt1>cnt2 and cnt3>cnt1
)
and invalid_reason is null;
commit;

--12
--deprecate drugs that have deprecated ingredients (all)
update concept_stage c set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (concept_code, vocabulary_id) in (
    select dss.drug_concept_code, dss.vocabulary_id_1 from drug_strength_stage dss, concept_stage cs
    where dss.ingredient_concept_code=cs.concept_code
    and dss.vocabulary_id_2=cs.vocabulary_id
    and vocabulary_id_1='RxNorm Extension'
    group by dss.drug_concept_code, dss.vocabulary_id_1
    having count(dss.ingredient_concept_code)=sum(case when cs.invalid_reason='D' then 1 else 0 end)
)
and invalid_reason is null;
commit;

--13
--deprecate drugs that link to each other and has different strength
update concept_relationship_stage crs set crs.invalid_reason='D', 
crs.valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension')
where crs.invalid_reason is null 
and (concept_code_1,vocabulary_id_1,concept_code_2,vocabulary_id_2) in (
    select concept_code_1,vocabulary_id_1,concept_code_2,vocabulary_id_2 from (
        select concept_code_1,vocabulary_id_1,concept_code_2,vocabulary_id_2 from (
            select distinct dss1.drug_concept_code as concept_code_1, dss1.vocabulary_id_1 as vocabulary_id_1, 
            dss2.drug_concept_code as concept_code_2, dss2.vocabulary_id_1 as vocabulary_id_2 
            from drug_strength_stage dss1, drug_strength_stage dss2
            where dss1.vocabulary_id_1 like 'RxNorm%'
            and dss2.vocabulary_id_1 like 'RxNorm%'
            and dss1.ingredient_concept_code=dss2.ingredient_concept_code
            and dss1.vocabulary_id_2=dss2.vocabulary_id_2
            and not (dss1.vocabulary_id_1='RxNorm' and dss2.vocabulary_id_1='RxNorm')
            and exists (
                select 1 from concept_relationship_stage crs
                where crs.concept_code_1=dss1.drug_concept_code 
                and crs.vocabulary_id_1=dss1.vocabulary_id_1
                and crs.concept_code_2=dss2.drug_concept_code 
                and crs.vocabulary_id_2=dss2.vocabulary_id_1
                and crs.invalid_reason is null
            )
            and (
                nvl (dss1.amount_value, dss1.numerator_value / nvl (dss1.denominator_value, 1)) / nvl (dss2.amount_value, dss2.numerator_value / nvl( dss2.denominator_value, 1)) >1.12
                or nvl (dss1.amount_value, dss1.numerator_value / nvl (dss1.denominator_value, 1)) / nvl (dss2.amount_value, dss2.numerator_value / nvl( dss2.denominator_value, 1)) < 0.9
            )
            and nvl (dss1.amount_unit_concept_id, (dss1.numerator_unit_concept_id+dss1.denominator_unit_concept_id)) = nvl (dss2.amount_unit_concept_id, (dss2.numerator_unit_concept_id+dss2.denominator_unit_concept_id))
        )
        --add a reverse
        unpivot ((concept_code_1,vocabulary_id_1,concept_code_2,vocabulary_id_2) 
		FOR relationships IN ((concept_code_1,vocabulary_id_1,concept_code_2,vocabulary_id_2),(concept_code_2,vocabulary_id_2,concept_code_1,vocabulary_id_1)))
    )
);
commit;

--14
--deprecate the drugs that have inaccurate dosage due to difference in ingredients subvarieties
--for ingredients with not null amount_value
update concept_stage c set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (concept_code, vocabulary_id) in (
    select dss.drug_concept_code, dss.vocabulary_id_1 from (
        select ingredient_concept_code, dosage, flag, count(distinct flag) over (partition by ingredient_concept_code, dosage_group) cnt_flags, 
		min (dosage) over (partition by ingredient_concept_code, dosage_group) min_dosage from (
            select rxe.ingredient_concept_code, rxe.dosage, rxe.dosage_group, nvl(rx.flag,rxe.flag) as flag from (
                select distinct ingredient_concept_code, dosage, dosage_group, 'bad' as flag 
                from (
                    select ingredient_concept_code, dosage, dosage_group, count(*) over(partition by ingredient_concept_code, dosage_group) as cnt_gr
                    from (
                        select ingredient_concept_code, dosage, sum(group_trigger) over (partition by ingredient_concept_code order by dosage)+1 dosage_group from (
                            select ingredient_concept_code, dosage, prev_dosage, abs(round((dosage-prev_dosage)*100/prev_dosage)) perc_dosage, 
                            case when abs(round((dosage-prev_dosage)*100/prev_dosage))<=5 then 0 else 1 end group_trigger from (
                                select 
                                ingredient_concept_code, dosage, lag(dosage,1,dosage) over (partition by ingredient_concept_code order by dosage) prev_dosage 
                                from (
                                    select distinct ingredient_concept_code, amount_value as dosage
                                    from drug_strength_stage  where vocabulary_id_1='RxNorm Extension' and  amount_value is not null             
                                )
                            ) 
                        )
                    )
                ) where cnt_gr > 1
            ) rxe,
            (
                select distinct ingredient_concept_code, amount_value as dosage, 'good' as flag 
                from drug_strength_stage  where vocabulary_id_1='RxNorm' and amount_value is not null
            ) rx
            where rxe.ingredient_concept_code=rx.ingredient_concept_code(+)
            and rxe.dosage=rx.dosage(+)
        )
    ) merged_rxe, drug_strength_stage dss 
    where (
        merged_rxe.flag='bad' and merged_rxe.cnt_flags=2 or
        merged_rxe.flag='bad' and merged_rxe.cnt_flags=1 and dosage<>min_dosage
    )
    and dss.ingredient_concept_code=merged_rxe.ingredient_concept_code
    and dss.amount_value=merged_rxe.dosage
    and dss.vocabulary_id_1='RxNorm Extension'
)
and invalid_reason is null;

--same, but for ingredients with null amount_value (instead, we use numerator_value or numerator_value/denominator_value)
update concept_stage c set invalid_reason='D',
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (concept_code, vocabulary_id) in (
    select dss.drug_concept_code, dss.vocabulary_id_1 from (
        select ingredient_concept_code, dosage, flag, count(distinct flag) over (partition by ingredient_concept_code, dosage_group) cnt_flags,
		min (dosage) over (partition by ingredient_concept_code, dosage_group) min_dosage from (
            select rxe.ingredient_concept_code, rxe.dosage, rxe.dosage_group, nvl(rx.flag,rxe.flag) as flag from (
                select distinct ingredient_concept_code, dosage, dosage_group, 'bad' as flag 
                from (
                    select ingredient_concept_code, dosage, dosage_group, count(*) over(partition by ingredient_concept_code, dosage_group) as cnt_gr
                    from (
                        select ingredient_concept_code, dosage, sum(group_trigger) over (partition by ingredient_concept_code order by dosage)+1 dosage_group from (
                            select ingredient_concept_code, dosage, prev_dosage, abs(round((dosage-prev_dosage)*100/prev_dosage)) perc_dosage, 
                            case when abs(round((dosage-prev_dosage)*100/prev_dosage))<=5 then 0 else 1 end group_trigger from (
                                select 
                                ingredient_concept_code, dosage, lag(dosage,1,dosage) over (partition by ingredient_concept_code order by dosage) prev_dosage 
                                from (
                                    select distinct ingredient_concept_code, round(dosage, 3-floor(log(10, dosage))-1) as dosage   
                                    from ( 
                                        select ingredient_concept_code,
                                        case when amount_value is null and denominator_value is null then 
                                            numerator_value
                                        else 
                                            numerator_value/denominator_value
                                        end as dosage
                                        from drug_strength_stage  where vocabulary_id_1='RxNorm Extension' and amount_value is null
                                    )           
                                )
                            ) 
                        )
                    )
                ) where cnt_gr > 1
            ) rxe,
            (
                select distinct ingredient_concept_code, round(dosage, 3-floor(log(10, dosage))-1) as dosage, 'good' as flag from 
                ( 
                    select ingredient_concept_code,
                    case when amount_value is null and denominator_value is null then 
                        numerator_value
                    else 
                        numerator_value/denominator_value
                    end as dosage                
                    from drug_strength_stage  where vocabulary_id_1='RxNorm' and amount_value is null
                )
            ) rx
            where rxe.ingredient_concept_code=rx.ingredient_concept_code(+)
            and rxe.dosage=rx.dosage(+)
        )
    ) merged_rxe, drug_strength_stage dss 
    where (
        merged_rxe.flag='bad' and merged_rxe.cnt_flags=2 or
        merged_rxe.flag='bad' and merged_rxe.cnt_flags=1 and dosage<>min_dosage
    )
    and dss.ingredient_concept_code=merged_rxe.ingredient_concept_code
    and dss.amount_value=merged_rxe.dosage
    and dss.vocabulary_id_1='RxNorm Extension'
)
and invalid_reason is null;
commit;

--15
--deprecate all mappings (except 'Maps to' and 'Drug has drug class') if RxE-concept was deprecated 
update concept_relationship_stage crs set crs.invalid_reason='D', 
crs.valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where exists (select 1 from concept_stage cs
    where cs.concept_code=crs.concept_code_1
    and cs.vocabulary_id=crs.vocabulary_id_1
    and cs.invalid_reason='D'
    and cs.vocabulary_id='RxNorm Extension'
)
and crs.relationship_id not in ('Maps to','Drug has drug class')
and crs.invalid_reason is null;

--reverse
update concept_relationship_stage crs set crs.invalid_reason='D', 
crs.valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where exists (select 1 from concept_stage cs
    where cs.concept_code=crs.concept_code_2
    and cs.vocabulary_id=crs.vocabulary_id_2
    and cs.invalid_reason='D'
    and cs.vocabulary_id='RxNorm Extension'
)
and crs.relationship_id not in ('Mapped from','Drug class of drug')
and crs.invalid_reason is null;
commit;

--16
--create temporary table with old mappings and fresh concepts (after all 'Concept replaced by')
create table rxe_tmp_replaces nologging as
with
src_codes as (
    --get concepts and all their links, which targets to 'U'
    select crs.concept_code_1 as src_code, crs.vocabulary_id_1 as src_vocab, 
    cs.concept_code upd_code, cs.vocabulary_id upd_vocab, 
    cs.concept_class_id upd_class_id, 
    crs.relationship_id src_rel
    From concept_stage cs, concept_relationship_stage crs
    where cs.concept_code=crs.concept_code_2
    and cs.vocabulary_id=crs.vocabulary_id_2
    and cs.invalid_reason='U'
    and cs.vocabulary_id='RxNorm Extension'
    and crs.invalid_reason is null
    and crs.relationship_id not in ('Concept replaced by','Concept replaces')
),
fresh_codes as (
    --get all fresh concepts (with recursion until the last fresh)
    select connect_by_root concept_code_1 as upd_code,
    connect_by_root vocabulary_id_1 upd_vocab,
    concept_code_2 new_code,
    vocabulary_id_2 new_vocab
    from (
        select * from concept_relationship_stage crs
        where crs.relationship_id='Concept replaced by'
        and crs.invalid_reason is null
        and crs.vocabulary_id_1='RxNorm Extension'
        and crs.vocabulary_id_2='RxNorm Extension'
    ) 
    where connect_by_isleaf = 1
    connect by nocycle prior concept_code_2 = concept_code_1 and prior vocabulary_id_2 = vocabulary_id_1
)
select src.src_code, src.src_vocab, src.upd_code, src.upd_vocab, src.upd_class_id, src.src_rel, fr.new_code, fr.new_vocab
from src_codes src, fresh_codes fr
where src.upd_code=fr.upd_code
and src.upd_vocab=fr.upd_vocab;

--deprecate old relationships
update concept_relationship_stage crs set crs.invalid_reason='D', 
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (crs.concept_code_1, crs.vocabulary_id_1, crs.concept_code_2, crs.vocabulary_id_2, crs.relationship_id) 
in (
    select r.src_code, r.src_vocab, r.upd_code, r.upd_vocab, r.src_rel from rxe_tmp_replaces r 
    where r.upd_class_id in ('Brand Name','Ingredient','Supplier','Dose Form')
);
--reverse
update concept_relationship_stage crs set crs.invalid_reason='D', 
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (crs.concept_code_1, crs.vocabulary_id_1, crs.concept_code_2, crs.vocabulary_id_2, crs.relationship_id) 
in (
    select r.upd_code, r.upd_vocab, r.src_code, r.src_vocab, rel.reverse_relationship_id from rxe_tmp_replaces r, relationship rel 
    where r.upd_class_id in ('Brand Name','Ingredient','Supplier','Dose Form')
    and r.src_rel=rel.relationship_id
);

--build new ones relationships or update existing
merge into concept_relationship_stage crs
using (
    select * from rxe_tmp_replaces r where 
    r.upd_class_id in ('Brand Name','Ingredient','Supplier','Dose Form')
) i
on (
    i.src_code=crs.concept_code_1
    and i.src_vocab=crs.vocabulary_id_1
    and i.new_code=crs.concept_code_2
    and i.new_vocab=crs.vocabulary_id_2
    and i.src_rel=crs.relationship_id
)
when matched then 
    update set crs.invalid_reason=null, crs.valid_end_date=to_date ('20991231', 'YYYYMMDD') where crs.invalid_reason is not null
when not matched then insert
(
    crs.concept_code_1,
    crs.vocabulary_id_1,
    crs.concept_code_2,
    crs.vocabulary_id_2,
    crs.relationship_id,
    crs.valid_start_date,
    crs.valid_end_date,
    crs.invalid_reason    
)
values
(
    i.src_code,
    i.src_vocab,
    i.new_code,
    i.new_vocab,
    i.src_rel,
    (SELECT latest_update FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension'),
    to_date ('20991231', 'YYYYMMDD'),
    null  
);

--reverse
merge into concept_relationship_stage crs
using (
    select * from rxe_tmp_replaces r, relationship rel where 
    r.upd_class_id in ('Brand Name','Ingredient','Supplier','Dose Form')
    and r.src_rel=rel.relationship_id
) i
on (
    i.src_code=crs.concept_code_2
    and i.src_vocab=crs.vocabulary_id_2
    and i.new_code=crs.concept_code_1
    and i.new_vocab=crs.vocabulary_id_1
    and i.reverse_relationship_id=crs.relationship_id
)
when matched then 
    update set crs.invalid_reason=null, crs.valid_end_date=to_date ('20991231', 'YYYYMMDD') where crs.invalid_reason is not null
when not matched then insert
(
    crs.concept_code_1,
    crs.vocabulary_id_1,
    crs.concept_code_2,
    crs.vocabulary_id_2,
    crs.relationship_id,
    crs.valid_start_date,
    crs.valid_end_date,
    crs.invalid_reason    
)
values
(
    i.new_code,
    i.new_vocab,
    i.src_code,
    i.src_vocab,
    i.reverse_relationship_id,
    (SELECT latest_update FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension'),
    to_date ('20991231', 'YYYYMMDD'),
    null  
);

--same for drugs (only deprecate old relationships except 'Maps to' and 'Drug has drug class' from 'U'
update concept_relationship_stage crs set crs.invalid_reason='D', 
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (crs.concept_code_1, crs.vocabulary_id_1, crs.concept_code_2, crs.vocabulary_id_2, crs.relationship_id) 
in (
    select r.src_code, r.src_vocab, r.upd_code, r.upd_vocab, r.src_rel from rxe_tmp_replaces r 
    where r.upd_class_id not in ('Brand Name','Ingredient','Supplier','Dose Form')
    and r.src_rel not in ('Mapped from','Drug class of drug')
);
--reverse
update concept_relationship_stage crs set crs.invalid_reason='D', 
valid_end_date=(SELECT latest_update-1 FROM vocabulary WHERE vocabulary_id = 'RxNorm Extension') 
where (crs.concept_code_1, crs.vocabulary_id_1, crs.concept_code_2, crs.vocabulary_id_2, crs.relationship_id) 
in (
    select r.upd_code, r.upd_vocab, r.src_code, r.src_vocab, rel.reverse_relationship_id from rxe_tmp_replaces r, relationship rel 
    where r.upd_class_id not in ('Brand Name','Ingredient','Supplier','Dose Form')
    and r.src_rel=rel.relationship_id
    and r.src_rel not in ('Mapped from','Drug class of drug')
);
commit;

--17 Working with replacement mappings
BEGIN
   DEVV5.VOCABULARY_PACK.CheckReplacementMappings;
END;
COMMIT;

--18 Deprecate 'Maps to' mappings to deprecated and upgraded concepts
BEGIN
   DEVV5.VOCABULARY_PACK.DeprecateWrongMAPSTO;
END;
COMMIT;

--19 Add mapping from deprecated to fresh concepts
BEGIN
   DEVV5.VOCABULARY_PACK.AddFreshMAPSTO;
END;
COMMIT;

--20 Delete ambiguous 'Maps to' mappings
BEGIN
   DEVV5.VOCABULARY_PACK.DeleteAmbiguousMAPSTO;
END;
COMMIT;

--21 Clean up
DROP TABLE rxe_tmp_replaces PURGE;

-- At the end, the three tables concept_stage, concept_relationship_stage and concept_synonym_stage should be ready to be fed into the generic_update.sql script