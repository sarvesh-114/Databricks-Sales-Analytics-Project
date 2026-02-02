create schema if not exists bronze;

create schema if not exists silver;

create schema if not exists gold;

select
  count(*)
from
  workspace.bronze.crm_cust_info;

select
  count(*)
from
  workspace.bronze.crm_sales_details;

select
  count(*)
from
  workspace.bronze.crm_prd_info;

select
  count(*)
from
  workspace.bronze.erp_cust_az_12;

select
  count(*)
from
  workspace.bronze.erp_loc_a_101;

select
  count(*)
from
  workspace.bronze.erp_px_cat_g_1_v_2;

drop table if exists silver.crm_cust_info;

create table silver.crm_cust_info (
  cst_id int,
  cst_key string,
  cst_firstnam string,
  cst_lastname string,
  cst_marital_status string,
  cst_gndr string,
  cst_create_date date,
  dwh__create_date timestamp
) using delta;

drop table if exists silver.crm_prd_info;

create table silver.crm_prd_info (
  prd_id int,
  cat_id string,
  prd_key string,
  prd_nm string,
  prd_cost int,
  prd_line string,
  prd_start_dt date,
  prd_end_dt date,
  dwh__create_date timestamp
) using delta;

drop table if exists silver.crm_sales_details;

create table silver.crm_sales_details (
  sls_ord_num string,
  sls_prd_key string,
  sls_cust_id int,
  sls_order_dt date,
  sls_ship_dt date,
  sls_due_dt date,
  sls_sales int,
  sls_quantity int,
  sls_price int,
  dwh__create_date timestamp
) using delta;

drop table if exists silver.erp_cust_az_12;

create table silver.erp_cust_az_12 (cid string, bdate date, gen string, dwh__create_date timestamp)
using delta;

drop table if exists silver.erp_px_cat_g_1_v_2;

create table silver.erp_px_cat_g_1_v_2 (
  id string,
  cat string,
  subcat string,
  maintainance string,
  dwh__create_date timestamp
) using delta;

drop table if exists silver.erp_loc_a_101;

create table silver.erp_loc_a_101 (cid string, cntry string, dwh__create_date timestamp)
using delta;

truncate table silver.crm_cust_info;

insert into silver.crm_cust_info (
  cst_id, cst_key, cst_firstnam, cst_lastname, cst_marital_status, cst_gndr, cst_create_date
)
  select
    cst_id,
    cst_key,
    trim(cst_firstname) as cst_firstnam,
    trim(cst_lastname) as cst_lastname,
    case
      when upper(trim(cst_marital_status)) = 'S' then 'single'
      when upper(trim(cst_marital_status)) = 'M' then 'married'
      else 'n/a'
    end as cst_marital_status,
    case
      when upper(trim(cst_gndr)) = 'F' then 'Female'
      when upper(trim(cst_gndr)) = 'M' then 'Male'
      else 'n/a'
    end as cst_gndr,
    cst_create_date
  from
    (
      select
        *,
        row_number() over (partition by cst_id order by cst_create_date desc) as flag_last
      from
        bronze.crm_cust_info
      where
        cst_id is not null
    ) t
  where
    flag_last = 1;

select
  *
from
  workspace.silver.crm_cust_info;

truncate table silver.crm_prd_info;

insert into silver.crm_prd_info (
  prd_id, cat_id, prd_key, prd_nm, prd_cost, prd_line, prd_start_dt, prd_end_dt
)
  select
    prd_id,
    replace(substring(prd_key, 1, 5), '-', '_') as cat_id,
    substring(prd_key, 7, length(prd_key)) as prd_key,
    prd_nm,
    coalesce(prd_cost, 0) as prd_cost,
    case
      when upper(trim(prd_line)) = 'M' then 'mountain'
      when upper(trim(prd_line)) = 'R' then 'road'
      when upper(trim(prd_line)) = 'S' then 'other sales'
      when upper(trim(prd_line)) = 'T' then 'touring'
      else 'not available'
    end as prd_line,
    cast(prd_start_dt as date) as prd_start_dt,
    cast(
      date_sub(lead(prd_start_dt) over (partition by prd_key order by prd_start_dt), 1) as date
    ) as prd_end_dt
  from
    bronze.crm_prd_info;

truncate table silver.crm_sales_details;

insert into silver.crm_sales_details (
  sls_ord_num,
  sls_prd_key,
  sls_cust_id,
  sls_order_dt,
  sls_ship_dt,
  sls_due_dt,
  sls_sales,
  sls_quantity,
  sls_price
)
  select
    sls_ord_num,
    sls_prd_key,
    sls_cust_id,
    case
      when
        sls_order_dt = 0
        or length(cast(sls_order_dt as string)) != 8
      then
        null
      else to_date(cast(sls_order_dt as string), 'yyyyMMdd')
    end as sls_order_dt,
    case
      when
        sls_ship_dt = 0
        or length(cast(sls_ship_dt as string)) != 8
      then
        null
      else to_date(cast(sls_ship_dt as string), 'yyyyMMdd')
    end as sls_ship_dt,
    case
      when
        sls_due_dt = 0
        or length(cast(sls_due_dt as string)) != 8
      then
        null
      else to_date(cast(sls_due_dt as string), 'yyyyMMdd')
    end as sls_due_dt,
    case
      when
        sls_sales is null
        or sls_sales <= 0
        or sls_sales != sls_quantity * abs(sls_price)
      then
        sls_quantity * abs(sls_price)
      else sls_sales
    end as sls_sales,
    sls_quantity,
    case
      when
        sls_price is null
        or sls_price <= 0
      then
        case
          when sls_quantity = 0 then null
          else sls_sales / sls_quantity
        end
      else sls_price
    end as sls_price
  from
    bronze.crm_sales_details;

truncate table silver.erp_cust_az_12;

insert into silver.erp_cust_az_12 (cid, bdate, gen)
  select
    case
      when cid like 'NAS%' then substring(cid, 4, len(cid))
      else cid
    end as cid,
    case
      when bdate > getdate() then null
      else bdate
    end as bdate,
    case
      when trim(gen) in ('M', 'Male') then 'Male'
      when trim(gen) in ('F', 'Female') then 'Female'
      else 'n/a'
    end as gen
  from
    bronze.erp_cust_az_12;

select distinct
  gen
from
  silver.erp_cust_az_12;

truncate table silver.erp_loc_a_101;

insert into silver.erp_loc_a_101 (cid, cntry)
  select
    replace(cid, '-', '') as cid,
    case
      when trim(cntry) in ('DE', 'germany') then 'Germany'
      when trim(cntry) in ('US', 'USA', 'united states') then 'United States'
      when
        cntry is null
        or trim(cntry) = ''
      then
        'n/a'
      else trim(cntry)
    end as cntry
  from
    bronze.erp_loc_a_101;

truncate table silver.erp_cust_az_12;

insert into silver.erp_px_cat_g_1_v_2 (id, cat, subcat, maintainance)
  select
    id,
    cat,
    subcat,
    maintenance
  from
    bronze.erp_px_cat_g_1_v_2;

create or replace view gold.dim_customers as
select
  row_number() over (order by cst_id) as customer_key,
  ci.cst_id as customer_id,
  ci.cst_key as customer_number,
  ci.cst_firstnam as firstname,
  ci.cst_lastname as lastname,
  ci.cst_marital_status as marital_status,
  case
    when ci.cst_gndr != 'n/a' then ci.cst_gndr
    else coalesce(ca.gen, 'n/a')
  end as gender,
  ci.cst_create_date as create_date,
  ca.bdate as birthdate,
  la.cntry as country
from
  silver.crm_cust_info ci
    left join silver.erp_cust_az_12 ca
      on ci.cst_key = ca.cid
    left join silver.erp_loc_a_101 la
      on ci.cst_key = la.cid;

select
  *
from
  gold.dim_customers;

create or replace view gold.dim_product as
select
  row_number() over (order by pn.prd_start_dt) as product_key,
  pn.prd_id as product_id,
  pn.cat_id as category_id,
  pc.cat as category,
  pc.subcat as subcategory,
  pn.prd_key as product_number,
  pn.prd_nm as product_name,
  pn.prd_cost as cost,
  pn.prd_line as product_line,
  pc.maintainance as maintenance,
  pn.prd_start_dt as start_date
from
  silver.crm_prd_info pn
    left join silver.erp_px_cat_g_1_v_2 pc
      on pn.cat_id = pc.id
where
  pn.prd_end_dt is null;

select
  *
from
  gold.dim_product;

create or replace view gold.fact_sales as
select
  sd.sls_ord_num as order_number,
  pr.product_key as product_key,
  cu.customer_key as customer_key,
  sd.sls_order_dt as order_date,
  sd.sls_ship_dt as ship_date,
  sd.sls_due_dt as due_date,
  sd.sls_sales as total_sales,
  sd.sls_quantity as total_quantity,
  sd.sls_price as total_price
from
  silver.crm_sales_details sd
    left join gold.dim_product pr
      on sd.sls_prd_key = pr.product_number
    left join gold.dim_customers cu
      on sd.sls_cust_id = cu.customer_id;

select
  *
from
  gold.fact_sales;
