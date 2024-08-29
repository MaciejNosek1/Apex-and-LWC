/**
 * @author        : Maciej Nosek
 * @created Date  : 08-07-2024
 * @description   : Apex class for ChangeOrderProcsses LWC
 **/
public with sharing class ChangeOrderProcess {
  static final string CHANGE_ORDER_PROCESS = 'ChangeOrderProcess';
  static final string PROCESS_CHANGE_ORDER = 'processChangeOrder';
  static final string CLONE_QUOTE_AND_LINES = 'cloneQuoteAndLines';
  static final string NON_COMMISSONABLE_CHANGE = 'Non Commissionable Change';
  static final string PRODUCT_MATERIAL_CHANGE = 'Product Material Change';
  static final string CONTRACT_AMOUNT_CHANGE = 'Contract Amount Change';
  static final string ORDER_TEAM_CHANGE = 'Order Team Change';
  public class ChangeOrderException extends Exception {
  }

  /**
   * @description : Main method to pull back orignal data, clone data and retunr the new Id
   * @param  : RecordId : Id, Type: String, TargetCustomerAmount: Decimal
   * @return  : New Quote Id
   **/

  @AuraEnabled
  public static Id processChangeOrder(
    Id recordId,
    String changeOrderType,
    Decimal targetCustomerAmount,
    List<Id> selectedOrderTeamIds,
    String newTeamMembersJson
  ) {
    if (
      changeOrderType == NON_COMMISSONABLE_CHANGE ||
      changeOrderType == PRODUCT_MATERIAL_CHANGE
    ) {
      Id quoteId = cloneQuoteAndLines(recordId, changeOrderType);
      return quoteId;
    } else if (changeOrderType == CONTRACT_AMOUNT_CHANGE) {
      Id orderId = cloneOrderAndLines(
        recordId,
        changeOrderType,
        targetCustomerAmount,
        null,
        null
      );

      return orderId;
    } else {
      Id orderId = cloneOrderAndLines(
        recordId,
        changeOrderType,
        targetCustomerAmount,
        selectedOrderTeamIds,
        newTeamMembersJson
      );

      return orderId;
    }
  }

  @AuraEnabled
  public static List<Order_Team_Member__c> getOrderTeam(Id recordId) {
    List<Order_Team_Member__c> orderTeam = [
      SELECT id, UserId__c, UserId__r.name, TeamMemberRole__c, Order_Access__c
      FROM Order_Team_Member__c
      WHERE OrderId__c = :recordId
    ];

    return orderTeam;
  }

  @AuraEnabled
  public static List<String> getTeamMemberRoles() {
    Map<String, String> roles = new Map<String, String>{};

    List<Schema.DescribeSobjectResult> results = Schema.describeSObjects(
      new List<String>{ 'Order_Team_Member__c' }
    );

    for (Schema.DescribeSobjectResult res : results) {
      for (
        Schema.PicklistEntry entry : res.fields.getMap()
          .get('TeamMemberRole__c')
          .getDescribe()
          .getPicklistValues()
      ) {
        if (entry.isActive()) {
          roles.put(entry.getValue(), entry.getLabel());
        }
      }
    }

    return new List<String>(roles.values());
  }

  /**
   * @description : Main method to pull back orignal data, clone data and retunr the new Id
   * @param  : OrderRecord : Order, quoteRecord : SBQQ__Quote__c, quoteLines: List<SBQQ__QuoteLine__c>, targetCustomerAmount : Decimal
   * @return  : New Quote Id
   **/

  private static Id cloneQuoteAndLines(Id orderId, String changeOrderType) {
    try {
      order orderRecord = getOrderRecord(orderId);
      SBQQ__Quote__c quote = getQuoteRecord(orderRecord.SBQQ__Quote__c);
      List<SBQQ__QuoteLine__c> quoteLines = getQuoteLineRecords(
        orderRecord.SBQQ__Quote__c
      );

      SBQQ__Quote__c clonedQuote = cloneQuote(quote, changeOrderType);

      updateParentOrderFieldsFromQuote(clonedQuote, orderRecord);

      insert clonedQuote;

      cloneQuoteLines(quoteLines, clonedQuote.Id);

      return clonedQuote.Id;
    } catch (Exception excep) {
      createErrorLog(CLONE_QUOTE_AND_LINES, excep);
      throw new ChangeOrderException(excep.getMessage());
    }
  }

  private static SBQQ__Quote__c cloneQuote(
    SBQQ__Quote__c quoteRecord,
    String changeOrderType
  ) {
    SBQQ__Quote__c clonedQuote = quoteRecord.clone(false, true, false, false);
    clonedQuote.SBQQ__Opportunity2__c = null;
    clonedQuote.SBQQ__Ordered__c = false;
    clonedQuote.Change_Order_Quote__c = true;
    clonedQuote.Change_Order_Type__c = changeOrderType;
    clonedQuote.CPQ_Approval_Status__c  = null;

    return clonedQuote;
  }

  private static void updateParentOrderFieldsFromQuote(
    SBQQ__Quote__c clonedQuote,
    Order orderRecord
  ) {
    if (orderRecord.Parent_Order__c == null) {
      clonedQuote.Parent_Order__c = orderRecord.Id;
    } else if (
      orderRecord.Parent_Order__c != null &&
      orderRecord.Parent_Change_Order__c == null
    ) {
      clonedQuote.Parent_Order__c = orderRecord.Parent_Order__c;
      clonedQuote.Parent_Change_Order__c = orderRecord.Id;
    } else if (
      orderRecord.Parent_Order__c != null &&
      orderRecord.Parent_Change_Order__c != null
    ) {
      clonedQuote.Parent_Order__c = orderRecord.Parent_Order__c;
      clonedQuote.Parent_Change_Order__c = orderRecord.Id;
    }

    if (orderRecord.Sales_Manager__c != null) {
      clonedQuote.CPQ_Sales_Manager__c = orderRecord.Sales_Manager__c;
    }

    if (orderRecord.OwnerId != null) {
      clonedQuote.CPQ_Installation_Manager__c = orderRecord.OwnerId;
    }
  }

  private static void cloneQuoteLines(
    List<SBQQ__QuoteLine__c> quoteLines,
    Id clonedQuoteId
  ) {
    Map<Id, SBQQ__QuoteLine__c> originalToClonedQuoteLineMap = new Map<Id, SBQQ__QuoteLine__c>();
    List<SBQQ__QuoteLine__c> clonedQuoteLines = new List<SBQQ__QuoteLine__c>();

    for (SBQQ__QuoteLine__c qli : quoteLines) {
      SBQQ__QuoteLine__c clonedQli = qli.clone(false, true, false, false);
      clonedQli.SBQQ__Quote__c = clonedQuoteId;
      originalToClonedQuoteLineMap.put(qli.Id, clonedQli);
      clonedQuoteLines.add(clonedQli);
    }

    try {
      insert clonedQuoteLines;
    } catch (Exception excep) {
      createErrorLog('cloneQuoteLines insert', excep);
      throw new ChangeOrderException(excep.getMessage());
    }

    for (SBQQ__QuoteLine__c clonedQli : clonedQuoteLines) {
      if (
        clonedQli.SBQQ__RequiredBy__c != null &&
        originalToClonedQuoteLineMap.containsKey(clonedQli.SBQQ__RequiredBy__c)
      ) {
        clonedQli.SBQQ__RequiredBy__c = originalToClonedQuoteLineMap.get(
            clonedQli.SBQQ__RequiredBy__c
          )
          .Id;
      }
    }

    try {
      update clonedQuoteLines;
    } catch (Exception excep) {
      createErrorLog('cloneQuoteLines update', excep);
      throw new ChangeOrderException(excep.getMessage());
    }
  }

  private static Id cloneOrderAndLines(
    Id orderId,
    String changeOrderType,
    Decimal targetCustomerAmount,
    List<Id> selectedOrderTeamIds,
    String newTeamMembersJson
  ) {
    Order orderRecord = getOrderRecord(orderId);
    List<OrderItem> orderLinesRecords = getOrderLineRecords(orderId);

    Order clonedOrder = cloneOrder(
      orderRecord,
      changeOrderType,
      targetCustomerAmount
    );

    List<TeamMember> newTeamMembers = new List<TeamMember>();
    if (newTeamMembersJson != null && String.isNotBlank(newTeamMembersJson)) {
      newTeamMembers = (List<TeamMember>) JSON.deserialize(
        newTeamMembersJson,
        List<TeamMember>.class
      );
    }

    try {
      SBQQ.TriggerControl.disable();
      updateParentOrderFieldsFromOrder(clonedOrder, orderRecord);
      insert clonedOrder;

      cloneOrderLines(orderLinesRecords, clonedOrder.Id);

      if (
        (newTeamMembers != null && !newTeamMembers.isEmpty()) ||
        (selectedOrderTeamIds != null && !selectedOrderTeamIds.isEmpty())
      ) {
        processOrderTeam(
          newTeamMembers,
          orderId,
          clonedOrder.Id,
          selectedOrderTeamIds
        );
      }

      return clonedOrder.Id;
    } catch (Exception excep) {
      createErrorLog('cloneOrderAndLines', excep);
      throw new ChangeOrderException(excep.getMessage());
    } finally {
      SBQQ.TriggerControl.enable();
    }
  }

  private static Order cloneOrder(
    Order orderRecord,
    String changeOrderType,
    Decimal targetCustomerAmount
  ) {
    Id chaangeOrderRt = Schema.SObjectType.Order.getRecordTypeInfosByDeveloperName()
      .get('Change_Order')
      .getRecordTypeId();

    Order clonedOrder = orderRecord.clone(false, true, false, false);
    clonedOrder.Status = 'IM Review';
    clonedOrder.Final_Contract_Amount__c = targetCustomerAmount;
    clonedOrder.RecordTypeId = chaangeOrderRt;
    clonedOrder.Type = changeOrderType;

    return clonedOrder;
  }

  private static void cloneOrderLines(
    List<OrderItem> orderLines,
    Id clonedOrderId
  ) {
    List<OrderItem> clonedOrderLines = new List<OrderItem>();

    for (OrderItem oli : orderLines) {
      OrderItem clonedOli = oli.clone(false, true, false, false);
      clonedOli.OrderId = clonedOrderId;

      clonedOrderLines.add(clonedOli);
    }

    try {
      insert clonedOrderLines;
    } catch (Exception excep) {
      createErrorLog('cloneOrderLines insert', excep);
      throw new ChangeOrderException(excep.getMessage());
    }
  }

  private static void updateParentOrderFieldsFromOrder(
    Order clonedOrder,
    Order orderRecord
  ) {
    if (orderRecord.Parent_Order__c == null) {
      clonedOrder.Parent_Order__c = orderRecord.Id;
    } else if (
      orderRecord.Parent_Order__c != null &&
      orderRecord.Parent_Change_Order__c == null
    ) {
      clonedOrder.Parent_Order__c = orderRecord.Parent_Order__c;
      clonedOrder.Parent_Change_Order__c = orderRecord.Id;
    } else if (
      orderRecord.Parent_Order__c != null &&
      orderRecord.Parent_Change_Order__c != null
    ) {
      clonedOrder.Parent_Order__c = orderRecord.Parent_Order__c;
      clonedOrder.Parent_Change_Order__c = orderRecord.Id;
    }
  }

  private static void processOrderTeam(
    List<TeamMember> newTeamMembers,
    String orderId,
    String clonedOrderId,
    List<Id> idsToDelete
  ) {
    Set<Id> idsToDeleteSet = idsToDelete != null
      ? new Set<Id>(idsToDelete)
      : new Set<Id>();
    List<Order_Team_Member__c> teamMembersToCreate = new List<Order_Team_Member__c>();

    for (Order_Team_Member__c otm : [
      SELECT Id, UserId__c, TeamMemberRole__c
      FROM Order_Team_Member__c
      WHERE
        OrderId__c = :orderId
        AND Id NOT IN :idsToDeleteSet
        AND UserId__c != NULL
        AND TeamMemberRole__c != NULL
    ]) {
      if (
        String.isNotBlank(otm.UserId__c) &&
        String.isNotBlank(otm.TeamMemberRole__c)
      ) {
        TeamMember member = new TeamMember();
        member.userId = otm.UserId__c;
        member.role = otm.TeamMemberRole__c;
        newTeamMembers.add(member);
      }
    }

    // Creating new team members for the cloned order
    for (TeamMember team : newTeamMembers) {
      if (String.isNotBlank(team.userId) && String.isNotBlank(team.role)) {
        Order_Team_Member__c otm = new Order_Team_Member__c();
        otm.OrderId__c = clonedOrderId;
        otm.Order_Access__c = 'Edit';
        otm.OwnerId = UserInfo.getUserId();
        otm.TeamMemberRole__c = team.role;
        otm.UserId__c = team.userId;
        teamMembersToCreate.add(otm);
      }
    }

    try {
      insert teamMembersToCreate;
    } catch (DmlException excep) {
      createErrorLog('deleteTeamMembers', excep);
      throw new ChangeOrderException(excep.getMessage());
    }
  }

  private static SBQQ__Quote__c getQuoteRecord(Id quoteId) {
    String query =
      'SELECT ' +
      getAllFields('SBQQ__Quote__c') +
      ' FROM SBQQ__Quote__c WHERE Id = :quoteId LIMIT 1';

    return Database.query(query);
  }

  private static List<SBQQ__QuoteLine__c> getQuoteLineRecords(Id quoteId) {
    String query =
      'SELECT ' +
      getAllFields('SBQQ__QuoteLine__c') +
      ' FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId';

    return Database.query(query);
  }

  private static Order getOrderRecord(Id orderId) {
    String query =
      'SELECT ' +
      getAllFields('Order') +
      ' FROM Order WHERE Id = :orderId LIMIT 1';

    return Database.query(query);
  }

  private static List<OrderItem> getOrderLineRecords(Id orderId) {
    String query =
      'SELECT ' +
      getAllFields('OrderItem') +
      ' FROM OrderItem WHERE OrderId = :orderId';

    return Database.query(query);
  }

  private static String getAllFields(String objectName) {
    Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
    Schema.SObjectType objectType = schemaMap.get(objectName);
    Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe()
      .fields.getMap();
    List<String> fieldList = new List<String>(fieldMap.keySet());

    return String.join(fieldList, ',');
  }

  private static void createErrorLog(String method, Exception excep) {
    Error_Log__c log = new Error_Log__c();
    log.Apex_Class__c = CHANGE_ORDER_PROCESS;
    log.Exception_Type__c = excep.getTypeName();
    log.Line_Number__c = String.valueOf(excep.getLineNumber());
    log.Stack_Trace__c = excep.getStackTraceString();
    log.Method__c = method;
    log.Exception_Message__c = excep.getMessage();
    log.RecordTypeId = Schema.SObjectType.Error_Log__c.getRecordTypeInfosByDeveloperName()
      .get('Automation_Error')
      .getRecordTypeId();
    log.OwnerId = UserInfo.getUserId();

    insert log;
  }

  public class TeamMember {
    @AuraEnabled
    public Id userId;
    @AuraEnabled
    public String role;
  }
}
