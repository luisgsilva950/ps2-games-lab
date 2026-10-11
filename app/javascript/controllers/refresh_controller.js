import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { active: Boolean, url: String }
  static targets = ["draft", "messages"]

  connect() {
    this.storageKey = `ps2-chat-draft:${window.location.pathname}`
    try {
      const saved = JSON.parse(sessionStorage.getItem(this.storageKey) || "null")
      if (saved && this.hasDraftTarget) {
        this.draftTarget.value = saved.content
        if (saved.focused && !this.draftTarget.disabled) {
          this.draftTarget.focus({ preventScroll: true })
          this.draftTarget.setSelectionRange(saved.start, saved.end)
        }
        window.scrollTo(0, saved.scroll)
      }
    } catch { /* Draft storage is optional. */ }
    if (this.activeValue) {
      this.events = new EventSource(this.urlValue)
      this.events.addEventListener("update", (event) => {
        const snapshot = JSON.parse(event.data)
        if (this.hasMessagesTarget) this.messagesTarget.innerHTML = snapshot.html
        if (!snapshot.active) {
          this.events.close()
          this.refresh()
        }
      })
    }
  }

  disconnect() { this.events?.close() }

  refresh() {
    try {
      sessionStorage.setItem(this.storageKey, JSON.stringify({
        content: this.hasDraftTarget ? this.draftTarget.value : "",
        focused: this.hasDraftTarget && document.activeElement === this.draftTarget,
        start: this.hasDraftTarget ? this.draftTarget.selectionStart : 0,
        end: this.hasDraftTarget ? this.draftTarget.selectionEnd : 0,
        scroll: window.scrollY
      }))
    } catch {
      // Keep an unsent draft when storage is unavailable; still enable sending after completion.
      if (this.hasDraftTarget && this.draftTarget.value) {
        this.element.querySelector('input[type="submit"]').disabled = false
        return
      }
    }
    Turbo.visit(window.location.href, { action: "replace" })
  }

  clearDraft() {
    this.events?.close()
    try { sessionStorage.removeItem(this.storageKey) } catch { /* No stored draft. */ }
  }
}
