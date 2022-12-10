libname plogit '/home/u62375736/sasuser.v94/FinalProject'; 

proc import 
datafile = "/home/u62375736/sasuser.v94/FinalProject/realtorDataNew.xlsx"
out = plogit.Houses	dbms = xlsx	replace;
getnames = yes;
run;


/* if data has . replace it with 0, create soldyear, drop status full_address street sold_date */
data plogit.Houses;
set plogit.Houses;
if bed =. then bed=0;
if bath =. then bath=0;
if house_size =. then delete;
if acre_lot = . then delete;
soldyear = year(sold_date);
drop status full_address street sold_date;
run;


/* checking if data has missing values */
proc means data = plogit.Houses nmiss;
run;

/* creating a new column nrow. It contains numbers from 1 to total row number */
data plogit.Houses;
set plogit.Houses;
nrow = _n_;
run;



/* creating macro to check if columns have outliers. */
%macro housing(var);
proc sgscatter data = plogit.Houses;
plot &var.*nrow;
run;

PROC SGPLOT  DATA = plogit.Houses;
   VBOX &var;
   title '&var. - Box Plot';
RUN; 

proc univariate data=plogit.Houses  ;
   var &var;
   histogram;
   output out= &var.Ptile pctlpts  = 0 0.1 0.2 0.3 0.4 0.5 1 2 90 95 97.5 99 99.5 99.6 99.7 99.8 99.9 100 pctlpre  = P;
run;

%mend;

/* checking price, bath, bed, acre_lot and house_size columns by using macro */
%housing(price);
%housing(bath);
%housing(bed);
%housing(acre_lot);
%housing(house_size);

/* deleting outliers */
data plogit.Houses;
set plogit.Houses;
if bed>13 then delete;
if bath>13 then delete;
if house_size>4932 then delete;
if acre_lot>6.15 then delete;
if price>10000000 then delete;
run;

/* check */

%housing(price);
%housing(bath);
%housing(bed);
%housing(acre_lot);
%housing(house_size);

/* bivariate for categorical. Calculating the avg price of states */

%macro bivariate(var);

proc sql;
create table &var._table as
select &var,avg(price) as Avg_priceBy&var
from plogit.Houses group by &var;
quit;
run;

proc sgplot data = &var._table;
vbar  &var/ response = Avg_priceBy&var stat = mean;
title &var._barchart;
run;

%mend;

%bivariate(state);
/* %bivariate(city); so much variables */

/* Creating a macro to Change categorical variables into numeric by calculating avg values. 
Then joining them with the main table again. */


%macro ChangeToNumeric(var);

proc sql;
create table &var._table as
select &var,avg(price) as Avg_priceBy&var
from plogit.Houses group by &var;
quit;
run;


proc sort data = plogit.Houses out =plogit.Houses;
by &var;
RUN;

proc sort data = &var._table out = &var._table ;
by &var;
RUN;

data plogit.Houses;
merge plogit.Houses(IN=a) &var._table(IN=b);
by &var;
if a = 1 and b = 1;
run;

%mend;

%ChangeToNumeric(city);
%ChangeToNumeric(state);
%ChangeToNumeric(zip_code);
%ChangeToNumeric(soldyear);



/* Checking correlation matrix to find significant relationships between price column and other columns */
proc corr data = plogit.Houses plots = matrix;
var price bed bath acre_lot house_size Avg_priceBycity Avg_priceBystate Avg_priceByzip_code Avg_priceBysoldyear;
run;

/* Insight 1) Price and House_size have strong correlation */
/* Insight 2) acre_lot and Avg_priceBystate and Avg_priceBysoldyear seem irrelevant with Price. */
/* Insight 3) Among the IV Avg_priceByzip_code & Avg_priceBycity are highly correlated which means keeping 
only one of them is enough. */


/*Checking correlation matrix again without irrelevant columns*/
proc corr data = plogit.Houses plots = matrix;
var price bed bath  house_size Avg_priceBycity Avg_priceByzip_code ;
run;

/* vif test */
proc reg data=plogit.Houses outest=pred1;
model price = Avg_priceByzip_code;
Output Out= LINREG;
run;

proc reg data=plogit.Houses outest=pred2;
model price = Avg_priceBycity ;
Output Out= LINREG;
run;

/* Avg_priceByzip_code Adj R-Sq	0.2668 */
/* Avg_priceBycity Adj R-Sq	0.2095 */
/* Result: Keep Avg_priceByzip_code  */

proc reg data = plogit.Houses outest=pred3;
model price = bed  bath  house_size Avg_priceBycity    ;
run;

/* no variable whose vif is more than 3 */
/* and also refering to Pr > |t| of bed and bath, both of them are not close to 0.001.(bed:0.0710 bath:0.1592)
Combining both as BedBath to see any change	 */

data plogit.Houses;
set plogit.Houses;
BedBath = bed + bath;
run;

proc reg data = plogit.Houses outest=pred3;
model price = BedBath  house_size Avg_priceBycity    ;
run;

/* Pr > |t| of BedBath shows 0.0092 which is lower then before(bed and bath).*/

/* finally, using BedBath,house_size,Avg_priceBycity for predicting price. */


/* BootStrap
Creating test and train tables and then running the model to test data. */


 %macro BootStrap(TestP,Seed);

proc sql outobs = %eval(&TestP*31459/100);
create table test as
select * from plogit.Houses
order by ranuni(&Seed);
quit;

proc sql;
create table train as 
select * from plogit.Houses
except
select * from test;
quit;

proc reg data=train outest=pred; 
model Price = BedBath House_Size Avg_priceBycity;
Output Out= TrainOut P= predicted R = residual; 
store out = ModelOut; 
run;

/* D. Run the model on test data */
proc plm source = ModelOut;
score data=test out=TestOut pred=predicted residual = residual;
run;

/* E. check residual metrics on test data */
proc sql;
create table residual_metrics_test as
select round(mean(abs(residual/Price))100,1) as mape, round(sqrt(mean(residual*2)),1) as rmse
from TestOut;
 quit;

%mend;


%BootStrap(20,100);	
%BootStrap(20,200);
%BootStrap(20,300);
%BootStrap(15,100);
%BootStrap(25,100); 
%BootStrap(30,100);
%BootStrap(30,200);

/* Finalizing the best model selected from bootstrapping exercise */

/* CHECK ALL THE 4 ASSUMPTIONS OF LINEAR REGRESSION */

/* Assumption test this should be close to 0*/
proc means data = TrainOut;
var residual;
run;


%let testPercentage = 20;
%let seed = 100;

proc sql outobs = %eval(&testPercentage*30581/100);
create table test as
select * from plogit.Houses
order by ranuni(&seed);
quit;

proc sql;
create table train as 
select * from plogit.Houses
except
select * from test;
quit;

/* run regresion model   */
proc reg data=train outest=pred4; 
model Price = BedBath House_Size Avg_priceBycity;
Output Out= TrainOut P= predicted R = residual; 
store out = ModelOut; 
run;


/*Descriptive analysis*/
/*Creating a table with predicted values*/
proc sql;
create table tbl_analysis as 
select city,soldyear, bed, bath, price,predicted from TrainOut;
quit;


/*Creating a table with predicted and actual values*/
proc sql;
create table tbl_analysis1 as
select bed,soldyear,round(avg(price)) as avgsold_price, round(avg(predicted)) as avgpredicted_price from TrainOut
group by bed, soldyear;
quit;

*Creating a table with predicted and actual values comparison*/
proc sql;
select * from  tbl_analysis1 
where soldyear=2021;
quit;

/*Plotting actual and predicted values*/
proc sgplot data= tbl_analysis2;
    series x= soldyear y = avgpredicted_price ;
    series x=soldyear y= avgsold_price; 
run;



