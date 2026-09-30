const watchedValues = root =>
  new Map(
    Array.from(root.querySelectorAll("[data-panel-watch]")).map(element => [
      element.dataset.panelWatch,
      {
        element,
        value: (element.textContent || "").replace(/\s+/gu, " ").trim()
      }
    ])
  )

const markChanged = (element, timers) => {
  const existingTimer = timers.get(element)
  if (existingTimer !== undefined) clearTimeout(existingTimer)

  element.classList.remove("board-state-changed")
  void element.offsetWidth
  element.classList.add("board-state-changed")

  const timer = setTimeout(() => {
    element.classList.remove("board-state-changed")
    timers.delete(element)
  }, 1100)
  timers.set(element, timer)
}

export const PanelPulse = {
  mounted() {
    this.values = watchedValues(this.el)
    this.pulseTimers = new Map()
    this.announcementTimer = null
  },

  beforeUpdate() {
    this.previousValues = watchedValues(this.el)
  },

  updated() {
    const previous = this.previousValues || this.values || new Map()
    const current = watchedValues(this.el)
    const changed = []

    for (const [key, next] of current) {
      if (previous.get(key)?.value !== next.value) {
        markChanged(next.element, this.pulseTimers)
        changed.push(key)
      }
    }

    this.previousValues = null
    this.values = current

    if (changed.length > 0) this.announceChange()
  },

  destroyed() {
    for (const timer of this.pulseTimers.values()) clearTimeout(timer)
    this.pulseTimers.clear()
    if (this.announcementTimer !== null) clearTimeout(this.announcementTimer)
  },

  announceChange() {
    const announcement = this.el.querySelector("[data-panel-announcement]")
    const message = this.el.dataset.panelChangeMessage
    if (!announcement || !message) return

    if (this.announcementTimer !== null) clearTimeout(this.announcementTimer)
    announcement.textContent = ""
    this.announcementTimer = setTimeout(() => {
      announcement.textContent = message
      this.announcementTimer = null
    }, 30)
  }
}
