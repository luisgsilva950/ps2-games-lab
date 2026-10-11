import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "zone", "filename", "feedback", "progress", "progressContainer", "submit"]

  disconnect() {
    if (this.request) this.request.abort()
  }

  selected() {
    this.filenameTarget.textContent = this.inputTarget.files[0]?.name || "One .iso image at a time"
    this.feedbackTarget.textContent = ""
  }

  dragover(event) {
    event.preventDefault()
    if (!this.request) this.zoneTarget.classList.add("is-dragging")
  }

  dragleave(event) {
    if (!this.zoneTarget.contains(event.relatedTarget)) this.zoneTarget.classList.remove("is-dragging")
  }

  drop(event) {
    event.preventDefault()
    this.zoneTarget.classList.remove("is-dragging")
    if (this.request) return
    const files = event.dataTransfer.files
    if (files.length !== 1 || !/\.iso$/i.test(files[0].name)) {
      this.feedbackTarget.textContent = "Choose one file with the .iso extension."
      return
    }
    this.inputTarget.files = files
    this.selected()
    this.inputTarget.focus()
    this.element.requestSubmit()
  }

  submit(event) {
    event.preventDefault()
    if (this.request) return
    const file = this.inputTarget.files[0]
    if (!file || !/\.iso$/i.test(file.name)) {
      this.feedbackTarget.textContent = "Choose one file with the .iso extension."
      this.inputTarget.focus()
      return
    }

    const data = new FormData(this.element)
    data.set("image", file)
    const request = new XMLHttpRequest()
    this.request = request
    this.submitTarget.disabled = true
    this.inputTarget.disabled = true
    this.progressContainerTarget.hidden = false
    this.progressTarget.value = 0
    this.feedbackTarget.textContent = "Uploading your ISO…"
    request.open("POST", this.element.action)
    request.setRequestHeader("Accept", "application/json")
    request.setRequestHeader("X-CSRF-Token", document.querySelector('meta[name="csrf-token"]').content)
    request.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        this.progressTarget.value = Math.round(event.loaded / event.total * 100)
        this.feedbackTarget.textContent = `${this.progressTarget.value}% uploaded`
      }
    }
    request.upload.onload = () => { this.feedbackTarget.textContent = "Upload complete. Preparing the import…" }
    request.onload = () => {
      let response
      try { response = JSON.parse(request.responseText) } catch { response = {} }
      if (request.status >= 200 && request.status < 300 && response.url) {
        window.location.assign(response.url)
      } else {
        const detail = response.error || response.errors
        this.fail(Array.isArray(detail) ? detail.join(". ") : detail || "Import could not be started. Please try again.")
      }
    }
    request.onerror = () => this.fail("Upload interrupted. Check your local server and try again.")
    request.onabort = () => { this.request = null }
    request.send(data)
  }

  fail(message) {
    this.request = null
    this.submitTarget.disabled = false
    this.inputTarget.disabled = false
    this.feedbackTarget.textContent = message
  }
}
