import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const draftSnapshots = new Map()

export default class extends Controller {
  static values = { active: Boolean, url: String }
  static targets = ["draft", "messages", "provider", "model", "conversation", "tuning"]

  connect() {
    this.storageKey = `ps2-chat-draft:${window.location.pathname}`
    this.savedScroll = undefined
    let saved = draftSnapshots.get(this.storageKey)
    draftSnapshots.delete(this.storageKey)
    try {
      saved ||= JSON.parse(sessionStorage.getItem(this.storageKey) || "null")
      sessionStorage.removeItem(this.storageKey)
    } catch { /* In-memory snapshots also preserve drafts without storage access. */ }
    if (saved && this.hasDraftTarget) {
      this.draftTarget.value = saved.content
      if (this.hasProviderTarget && saved.provider) this.providerTarget.value = saved.provider
      if (this.hasModelTarget && saved.model !== undefined) this.modelTarget.value = saved.model
      this.element.dispatchEvent(new CustomEvent("provider:restore"))
      if (this.hasConversationTarget && saved.conversationOpen !== undefined) this.conversationTarget.open = saved.conversationOpen
      if (saved.tuning) this.tuningTargets.forEach((field) => {
        if (Object.hasOwn(saved.tuning, field.dataset.tuningKey)) field.value = saved.tuning[field.dataset.tuningKey]
      })
      const focused = saved.focusedTarget && this[`${saved.focusedTarget}Target`]
      if (focused && !focused.disabled) {
        focused.focus({ preventScroll: true })
        if (saved.start != null && focused.setSelectionRange) focused.setSelectionRange(saved.start, saved.end)
      }
      this.savedScroll = saved.scroll
      requestAnimationFrame(() => this.restoreScroll())
    }
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

  restoreScroll() {
    if (this.savedScroll !== undefined) window.scrollTo(0, this.savedScroll)
  }

  refresh() {
    const focusedTarget = ["draft", "provider", "model"].find((name) =>
      this[`has${name[0].toUpperCase()}${name.slice(1)}Target`] && document.activeElement === this[`${name}Target`]
    )
    this.rememberComposer(this.hasDraftTarget ? this.draftTarget.value : "", focusedTarget, true)
    Turbo.visit(window.location.href, { action: "replace" })
  }

  preserveWorkspace() {
    this.events?.close()
    this.rememberComposer(this.hasDraftTarget ? this.draftTarget.value : "")
  }

  prepareSubmission() {
    this.events?.close()
    this.rememberComposer("", "draft")
  }

  rememberComposer(content, focusedTarget, preserveTuning = false) {
    const focused = focusedTarget && this[`${focusedTarget}Target`]
    const saved = {
      content,
      provider: this.hasProviderTarget ? this.providerTarget.value : undefined,
      model: this.hasModelTarget ? this.modelTarget.value : undefined,
      conversationOpen: this.hasConversationTarget ? this.conversationTarget.open : undefined,
      tuning: preserveTuning ? Object.fromEntries(this.tuningTargets.map((field) => [field.dataset.tuningKey, field.value])) : undefined,
      focusedTarget,
      start: focused?.selectionStart,
      end: focused?.selectionEnd,
      scroll: window.scrollY
    }
    draftSnapshots.set(this.storageKey, saved)
    try { sessionStorage.setItem(this.storageKey, JSON.stringify(saved)) } catch { /* Use the in-memory snapshot. */ }
  }
}
