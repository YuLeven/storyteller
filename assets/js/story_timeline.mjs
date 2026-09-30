const revealDelayMs = 520
const immediateEventTypes = new Set(["player_action", "player_roll", "roll_request"])

const entriesFor = element => Array.from(element.querySelectorAll("[data-event-sequence]"))
const sequenceFor = entry => Number(entry.dataset.eventSequence)
const eventTypeFor = entry => entry.dataset.eventType

const reducedMotionRequested = () =>
  typeof window !== "undefined" &&
  typeof window.matchMedia === "function" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches

const announcementText = (entry, prefix) => {
  const content = (entry.innerText || entry.textContent || "").replace(/\s+/gu, " ").trim()
  const excerpt = content.length > 260 ? `${content.slice(0, 257).trimEnd()}…` : content
  return excerpt ? `${prefix} ${excerpt}`.trim() : prefix
}

export const StoryTimeline = {
  mounted() {
    this.knownSequences = new Set(entriesFor(this.el).map(sequenceFor))
    this.latestSequence = Math.max(0, ...this.knownSequences)
    this.followLatest = true
    this.revealQueue = []
    this.revealTimer = null
    this.reducedMotion =
      typeof this.reducedMotion === "boolean" ? this.reducedMotion : reducedMotionRequested()
    this.liveTimeline = this.el.querySelector("#story-live-timeline")
    this.revealControls = this.el.querySelector("#story-reveal-controls")
    this.showAllButton = this.el.querySelector("[data-story-show-all]")
    this.announcement = this.el.querySelector("#story-reveal-announcement")

    // The status region announces one new event at a time. The list itself is
    // turned off after mount so a fast GM response cannot flood screen readers.
    this.liveTimeline?.setAttribute("aria-live", "off")

    this.onScroll = () => {
      this.followLatest = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 96
    }
    this.onShowAll = event => {
      event.preventDefault()
      this.showAllNewEvents()
    }

    this.el.addEventListener("scroll", this.onScroll, {passive: true})
    this.showAllButton?.addEventListener("click", this.onShowAll)
    this.scrollLatest()
  },

  beforeUpdate() {
    this.scrollSnapshot = {height: this.el.scrollHeight, top: this.el.scrollTop}
  },

  updated() {
    const scrollSnapshot = this.scrollSnapshot
    this.scrollSnapshot = null
    const currentEntries = entriesFor(this.el)
    const newEntries = currentEntries
      .filter(entry => !this.knownSequences.has(sequenceFor(entry)))
      .sort((left, right) => sequenceFor(left) - sequenceFor(right))

    for (const entry of newEntries) this.knownSequences.add(sequenceFor(entry))

    if (newEntries.length === 0) {
      if (this.followLatest) this.scrollLatest()
      return
    }

    const appendedEntries = newEntries.filter(entry => sequenceFor(entry) > this.latestSequence)
    this.latestSequence = Math.max(this.latestSequence, ...newEntries.map(sequenceFor))

    // Loading older campaign history prepends entries. It is immediately
    // available to read and never treated as newly arriving GM output.
    if (appendedEntries.length === 0) {
      if (newEntries.length > 0 && scrollSnapshot) {
        this.el.scrollTop = scrollSnapshot.top + (this.el.scrollHeight - scrollSnapshot.height)
      }

      return
    }

    const immediateEntries = appendedEntries.filter(entry =>
      immediateEventTypes.has(eventTypeFor(entry))
    )
    const arrivingEntries = appendedEntries.filter(
      entry => !immediateEventTypes.has(eventTypeFor(entry))
    )

    for (const entry of immediateEntries) this.reveal(entry)

    if (appendedEntries.some(entry => eventTypeFor(entry) === "player_action")) {
      // The canonical player-action event is already durable. Keep it visible
      // in the story viewport instead of rendering a second optimistic copy.
      this.followLatest = true
      this.scrollLatest()
    }

    if (arrivingEntries.length === 0) return

    for (const entry of arrivingEntries) {
      entry.setAttribute("data-reveal-pending", "true")
      this.revealQueue.push(entry)
    }

    if (this.reducedMotion) {
      this.showAllNewEvents(false)
      this.announce(this.el.dataset.storyAllReady || "New story is ready.")
    } else {
      if (this.revealControls) this.revealControls.hidden = false
      this.scheduleNextReveal()
    }
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll)
    this.showAllButton?.removeEventListener("click", this.onShowAll)
    if (this.revealTimer !== null) clearTimeout(this.revealTimer)
  },

  scrollLatest() {
    requestAnimationFrame(() => {
      this.el.scrollTop = this.el.scrollHeight
    })
  },

  scheduleNextReveal() {
    if (this.revealTimer !== null || this.revealQueue.length === 0) return

    this.revealTimer = setTimeout(() => {
      this.revealTimer = null
      const [entry, ...remaining] = this.revealQueue
      this.revealQueue = remaining
      this.reveal(entry)

      if (this.followLatest) this.scrollLatest()
      if (this.revealQueue.length === 0) {
        this.revealControls.hidden = true
      } else {
        this.scheduleNextReveal()
      }
    }, revealDelayMs)
  },

  reveal(entry) {
    entry.removeAttribute("data-reveal-pending")
    entry.classList.add("story-entry-revealed")
    this.announce(announcementText(entry, this.el.dataset.storyAnnouncementPrefix || "New story:"))
  },

  announce(message) {
    if (this.announcement) this.announcement.textContent = message
  },

  showAllNewEvents(announce = true) {
    if (this.revealTimer !== null) {
      if (this.clearRevealTimer) {
        this.clearRevealTimer(this.revealTimer)
      } else {
        clearTimeout(this.revealTimer)
      }
      this.revealTimer = null
    }

    for (const entry of this.revealQueue) this.reveal(entry)
    this.revealQueue = []
    if (this.revealControls) this.revealControls.hidden = true
    if (announce) this.announce(this.el.dataset.storyAllReady || "New story is ready.")
    if (this.followLatest) this.scrollLatest()
  }
}
