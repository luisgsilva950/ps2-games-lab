import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["provider", "model", "notice", "label"]
  static values = { models: Object, notices: Object }

  connect() { this.restore() }

  change() {
    this.modelTarget.value = this.modelsValue[this.providerTarget.value] || ""
    this.restore()
  }

  restore() {
    const notice = this.noticesValue[this.providerTarget.value] || ""
    this.noticeTarget.textContent = notice
    this.noticeTarget.hidden = !notice
    this.labelTarget.textContent = this.providerTarget.selectedOptions[0]?.textContent || "the selected provider"
  }
}
