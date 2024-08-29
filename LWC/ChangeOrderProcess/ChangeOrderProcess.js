import { LightningElement, api, track } from "lwc";
import processChangeOrder from "@salesforce/apex/ChangeOrderProcess.processChangeOrder";
import getOrderTeam from "@salesforce/apex/ChangeOrderProcess.getOrderTeam";
import getTeamMemberRoles from "@salesforce/apex/ChangeOrderProcess.getTeamMemberRoles";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import { NavigationMixin } from "lightning/navigation";

export default class ChangeOrderProcess extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @track selectedRadioOption;
  @track targetCustomerAmount;
  @track showSpinner = false;
  @track showChangeOrderPage = true;
  @track showOrderTeamPage = false;
  @track showConfirmationPage = false;
  @track orderTeamMembers = [];
  @track selectedOrderTeamIds = [];
  @track newTeamMembers = [{ userId: "", role: "" }];
  @track teamMemberRoles = [];
  @track addMembers = "No";

  static ERROR_TITLE = "Error";
  static SUCCESS_TITLE = "Success";
  static CONTRACT_AMOUNT_CHANGE = "Contract Amount Change";
  static NON_COMM_TYPE = "Non Commissionable Change";
  static PROD_MATERIAL_CHANGE = "Product Material Change";
  static ORDER_TEAM_CHANGE = "Order Team Change";

  connectedCallback() {
    this.loadTeamMemberRoles();
  }

  async loadTeamMemberRoles() {
    try {
      const roles = await getTeamMemberRoles();
      this.teamMemberRoles = roles.map((role) => ({
        label: role,
        value: role
      }));
    } catch (error) {
      this.handleError(error);
    }
  }

  handleNextButton() {
    if (!this.validateInputs()) {
      return;
    }

    if (this.selectedRadioOption === ChangeOrderProcess.ORDER_TEAM_CHANGE) {
      if (this.showOrderTeamPage) {
        this.showConfirmationPage = true;
        this.showOrderTeamPage = false;
      } else {
        this.showOrderTeamPage = true;
        this.showChangeOrderPage = false;
        this.fetchOrderTeamMembers();
      }
    } else {
      this.showConfirmationPage = true;
      this.showChangeOrderPage = false;
    }
  }

  handleBack() {
    if (this.showConfirmationPage) {
      this.showConfirmationPage = false;
      if (this.selectedRadioOption === ChangeOrderProcess.ORDER_TEAM_CHANGE) {
        this.showOrderTeamPage = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.preselectTeamMembers(), 10);
      } else {
        this.showChangeOrderPage = true;
      }
    } else if (this.showOrderTeamPage) {
      this.showOrderTeamPage = false;
      this.showChangeOrderPage = true;
    }
  }

  handleSaveButton() {
    this.setShowSpinner(true);
    this.handleSave();
  }

  async handleSave() {
    this.setShowSpinner(true);

    if (this.selectedRadioOption !== ChangeOrderProcess.ORDER_TEAM_CHANGE) {
      this.newTeamMembers = [{ userId: "", role: "" }];
      this.selectedOrderTeamIds = [];
    }

    try {
      const recordId = await processChangeOrder({
        recordId: this.recordId,
        changeOrderType: this.selectedRadioOption,
        targetCustomerAmount: this.targetCustomerAmount,
        selectedOrderTeamIds: this.selectedOrderTeamIds,
        newTeamMembersJson: JSON.stringify(this.newTeamMembers)
      });

      this.showToast(
        ChangeOrderProcess.SUCCESS_TITLE,
        `${this.selectedRadioOption} executed successfully`,
        "success"
      );

      if (this.selectedRadioOption === ChangeOrderProcess.NON_COMM_TYPE) {
        this.navigateToQuoteEditProducts(recordId);
      } else if (
        this.selectedRadioOption === ChangeOrderProcess.PROD_MATERIAL_CHANGE
      ) {
        this.navigateToQuoteEditProducts(recordId);
      } else {
        this.navigateToOrder(recordId);
      }
    } catch (error) {
      this.handleError(error);
    } finally {
      this.setShowSpinner(false);
      this.closeQuickAction();
    }
  }

  handleRadioButtonChange({ detail: { value } }) {
    this.selectedRadioOption = value;
  }

  handleAmountChange({ detail: { value } }) {
    this.targetCustomerAmount = value;
  }

  handleAddMembersChange({ detail: { value } }) {
    this.addMembers = value;
  }

  closeQuickAction() {
    this.dispatchEvent(new CloseActionScreenEvent("close"));
  }

  showToast(title, message, variant) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: variant
      })
    );
  }

  validateInputs() {
    if (!this.recordId || !this.selectedRadioOption) {
      this.showValidationError("Please select an option");
      return false;
    }
    if (
      this.selectedRadioOption === ChangeOrderProcess.CONTRACT_AMOUNT_CHANGE &&
      !this.targetCustomerAmount
    ) {
      this.showValidationError("Please fill in the Target Customer Amount");
      return false;
    }
    if (
      this.showOrderTeamPage &&
      this.selectedRadioOption === ChangeOrderProcess.ORDER_TEAM_CHANGE &&
      this.selectedOrderTeamIds.length === 0 &&
      this.newTeamMembers.every((member) => !member.userId || !member.role)
    ) {
      this.showValidationError(
        "A team member needs to be added or selected to proceed"
      );
      return false;
    }
    return true;
  }

  showValidationError(message) {
    this.showToast(ChangeOrderProcess.ERROR_TITLE, message, "error");
  }

  handleError(error) {
    console.error(
      "Error in handleSave:",
      error,
      "Record ID:",
      this.recordId,
      "Selected Value:",
      this.selectedRadioOption
    );
    const message = error.body ? error.body.message : error.message;
    this.showToast(ChangeOrderProcess.ERROR_TITLE, message, "error");
  }

  setShowSpinner(state) {
    this.showSpinner = state;
  }

  navigateToQuoteEditProducts(recordId) {
    const link = `/apex/sbqq__sb?scontrolCaching=1&id=${recordId}#quote/le?qId=${recordId}`;

    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: link
      }
    });
  }

  // navigateToQuote(recordId) {
  //   this[NavigationMixin.Navigate]({
  //     type: "standard__recordPage",
  //     attributes: {
  //       recordId: recordId,
  //       objectApiName: "Quote",
  //       actionName: "view"
  //     }
  //   });
  // }

  navigateToOrder(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        objectApiName: "Order",
        actionName: "view"
      }
    });
  }

  async fetchOrderTeamMembers() {
    this.setShowSpinner(true);
    try {
      const data = await getOrderTeam({ recordId: this.recordId });
      this.orderTeamMembers = data.map((member) => ({
        ...member,
        userName: member.UserId__r ? member.UserId__r.Name : ""
      }));
      this.preselectTeamMembers();
    } catch (error) {
      this.showToast("Error", "Error fetching order team members", "error");
      console.error("Error fetching order team members:", error);
    } finally {
      this.setShowSpinner(false);
    }
  }

  handleOrderKeepTeamMemberSelection(event) {
    const selectedId = event.target.dataset.id;
    if (event.target.checked) {
      if (!this.selectedOrderTeamIds.includes(selectedId)) {
        this.selectedOrderTeamIds = [...this.selectedOrderTeamIds, selectedId];
      }
    } else {
      this.selectedOrderTeamIds = this.selectedOrderTeamIds.filter(
        (id) => id !== selectedId
      );
    }
  }

  handleAddTeamMember() {
    this.newTeamMembers.push({ userId: "", role: "" });
  }

  handleAddUser(event) {
    const index = event.target.dataset.index;
    this.newTeamMembers[index].userId = event.detail.recordId;
  }

  handleTeamRoleChange(event) {
    const index = event.target.dataset.index;
    this.newTeamMembers[index].role = event.detail.value;
  }

  get showAddTeamSection() {
    return this.addMembers === "Yes";
  }

  get showTargetCustomerAmount() {
    return (
      this.selectedRadioOption === ChangeOrderProcess.CONTRACT_AMOUNT_CHANGE
    );
  }

  get noOrderTeam() {
    return this.orderTeamMembers.length === 0;
  }

  get radioOptions() {
    return [
      {
        label: ChangeOrderProcess.NON_COMM_TYPE,
        value: ChangeOrderProcess.NON_COMM_TYPE
      },
      {
        label: ChangeOrderProcess.PROD_MATERIAL_CHANGE,
        value: ChangeOrderProcess.PROD_MATERIAL_CHANGE
      },
      {
        label: ChangeOrderProcess.CONTRACT_AMOUNT_CHANGE,
        value: ChangeOrderProcess.CONTRACT_AMOUNT_CHANGE
      },
      {
        label: ChangeOrderProcess.ORDER_TEAM_CHANGE,
        value: ChangeOrderProcess.ORDER_TEAM_CHANGE
      }
    ];
  }

  get addMembersOptions() {
    return [
      { label: "Yes", value: "Yes" },
      { label: "No", value: "No" }
    ];
  }

  preselectTeamMembers() {
    console.log(
      "Preselecting team members:",
      JSON.stringify(this.selectedOrderTeamIds)
    );
    const inputs = this.template.querySelectorAll("lightning-input[data-id]");
    inputs.forEach((input) => {
      if (this.selectedOrderTeamIds.includes(input.dataset.id)) {
        input.checked = true;
      } else {
        input.checked = false;
      }
    });
  }
}
