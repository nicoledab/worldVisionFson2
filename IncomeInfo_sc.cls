/************************************************************************************
 * Description :
 * Ver      Date           Author          Modification
 * ===================================================================================
   1.0      2023-02-09     hs.jung          Create
*************************************************************************************/

global class IncomeInfo_sc implements Schedulable {

    global void execute(SchedulableContext sc) {

        Database.executeBatch(new IncomeInfo_ba(system.today().addDays(-1)));
    }
}