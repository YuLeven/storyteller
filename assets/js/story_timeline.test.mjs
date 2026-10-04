import test from "node:test"
import assert from "node:assert/strict"
import {StoryTimeline} from "./story_timeline.mjs"

class FakeClassList {
  values = new Set()
  add(value) { this.values.add(value) }
  remove(value) { this.values.delete(value) }
  contains(value) { return this.values.has(value) }
}

class FakeEntry {
  constructor(sequence, type, text = `Message ${sequence}`) {
    this.dataset = {eventSequence: String(sequence), eventType: type}
    this.textContent = text
    this.innerText = text
    this.attributes = new Set()
    this.classList = new FakeClassList()
  }
  setAttribute(name) { this.attributes.add(name) }
  removeAttribute(name) { this.attributes.delete(name) }
  hasAttribute(name) { return this.attributes.has(name) }
}

class FakeTarget {
  constructor() { this.listeners = new Map() }
  addEventListener(name, callback) { this.listeners.set(name, callback) }
  removeEventListener(name) { this.listeners.delete(name) }
}

class FakeTimeline extends FakeTarget {
  constructor(entries = [], reducedMotion = false) {
    super()
    this.entries = entries
    this.dataset = {
      storyAnnouncementPrefix: "New story:",
      storyAllReady: "New story is ready."
    }
    this.scrollHeight = 1_000
    this.scrollTop = 0
    this.clientHeight = 300
    this.liveTimeline = {attributes: {}, setAttribute(name, value) { this.attributes[name] = value }}
    this.controls = {hidden: true}
    this.announcement = {textContent: ""}
    this.button = new FakeTarget()
    this.button.prevented = false
    this.reducedMotion = reducedMotion
  }
  querySelectorAll(selector) {
    assert.equal(selector, "[data-event-sequence]")
    return this.entries
  }
  querySelector(selector) {
    return {
      "#story-live-timeline": this.liveTimeline,
      "#story-reveal-controls": this.controls,
      "[data-story-show-all]": this.button,
      "#story-reveal-announcement": this.announcement
    }[selector] || null
  }
}

const createContext = (el, reducedMotion = false) => {
  let pendingTimers = []
  return {
    el,
    ...StoryTimeline,
    schedule(callback) { pendingTimers.push(callback) },
    cancelTimer() { pendingTimers = [] },
    clearRevealTimer() { pendingTimers = [] },
    runNext() { pendingTimers.shift()?.() },
    timerCount() { return pendingTimers.length },
    reducedMotion,
    scrollLatest() { this.el.scrollTop = this.el.scrollHeight },
    scheduleInitialScroll() { this.scrollLatest() },
    scheduleNextReveal() {
      if (this.revealTimer !== null || this.revealQueue.length === 0) return
      this.revealTimer = 1
      this.schedule(() => {
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
      })
    },
    destroyed() {
      this.el.removeEventListener("scroll", this.onScroll)
      this.showAllButton?.removeEventListener("click", this.onShowAll)
      this.cancelTimer()
    }
  }
}

test("existing history appears immediately on mount without replaying", () => {
  const history = [new FakeEntry(1, "gm_narration"), new FakeEntry(2, "npc_dialogue")]
  const el = new FakeTimeline(history)
  const context = createContext(el)

  context.mounted()

  assert.deepEqual(context.revealQueue, [])
  assert.equal(context.timerCount(), 0)
  assert.equal(el.controls.hidden, true)
  assert.equal(el.scrollTop, el.scrollHeight)
  assert.equal(el.liveTimeline.attributes["aria-live"], "off")
  assert.ok(history.every(entry => !entry.hasAttribute("data-reveal-pending")))
})

test("a fresh timeline aligns to the latest entry after initial layout settles", () => {
  const originalRequestAnimationFrame = globalThis.requestAnimationFrame
  const originalCancelAnimationFrame = globalThis.cancelAnimationFrame
  const queuedFrames = new Map()
  let nextFrameId = 0
  globalThis.requestAnimationFrame = callback => {
    const id = ++nextFrameId
    queuedFrames.set(id, callback)
    return id
  }
  globalThis.cancelAnimationFrame = id => queuedFrames.delete(id)

  const runNextFrame = () => {
    const next = queuedFrames.entries().next().value
    if (!next) return
    const [id, callback] = next
    queuedFrames.delete(id)
    callback()
  }

  const el = new FakeTimeline([new FakeEntry(1, "gm_narration"), new FakeEntry(2, "npc_dialogue")])
  const context = Object.assign({el}, StoryTimeline)
  const readerEl = new FakeTimeline([new FakeEntry(1, "gm_narration")])
  const readerContext = Object.assign({el: readerEl}, StoryTimeline)
  const prependEl = new FakeTimeline([new FakeEntry(8, "gm_narration")])
  const prependContext = Object.assign({el: prependEl}, StoryTimeline)

  try {
    context.mounted()
    assert.equal(queuedFrames.size, 1)

    // The first frame runs before the initial layout/LiveView patch has
    // reached its final height. A single-frame scroll would stop here.
    runNextFrame()
    assert.equal(queuedFrames.size, 1)
    assert.equal(el.scrollTop, 0)

    el.scrollHeight = 1_800
    runNextFrame()

    assert.equal(el.scrollTop, 1_800)
    assert.equal(context.followLatest, true)

    readerContext.mounted()
    runNextFrame()
    readerEl.scrollTop = 120
    readerContext.onScroll()
    readerEl.scrollHeight = 1_800
    runNextFrame()

    assert.equal(readerEl.scrollTop, 120)
    assert.equal(readerContext.followLatest, false)

    prependContext.mounted()
    prependEl.scrollTop = 120
    prependContext.onScroll()
    prependContext.beforeUpdate()
    prependEl.entries.unshift(new FakeEntry(3, "player_action"))
    prependEl.scrollHeight += 240
    prependContext.updated()

    assert.equal(queuedFrames.size, 0)
    assert.equal(prependEl.scrollTop, 360)
    assert.equal(prependContext.followLatest, false)
  } finally {
    context.destroyed()
    readerContext.destroyed()
    prependContext.destroyed()
    globalThis.requestAnimationFrame = originalRequestAnimationFrame
    globalThis.cancelAnimationFrame = originalCancelAnimationFrame
  }
})

test("a new player action is immediate while a batched GM response is paced and skippable", () => {
  const el = new FakeTimeline([new FakeEntry(1, "gm_narration")])
  const context = createContext(el)
  context.mounted()
  el.scrollTop = 0
  context.onScroll()

  const incoming = [
    new FakeEntry(2, "player_action", "I open the orchard gate."),
    new FakeEntry(3, "gm_narration", "The latch gives way."),
    new FakeEntry(4, "npc_dialogue", "Inés calls from the press."),
    new FakeEntry(5, "character_activity", "She sets down the basket."),
    new FakeEntry(6, "state_change", "The gate is open."),
    new FakeEntry(7, "gm_narration", "The path beyond is clear.")
  ]
  el.entries.push(...incoming)
  context.updated()

  assert.ok(!incoming[0].hasAttribute("data-reveal-pending"))
  assert.ok(incoming.slice(1).every(entry => entry.hasAttribute("data-reveal-pending")))
  assert.equal(context.revealQueue.length, 5)
  assert.equal(el.controls.hidden, false)
  assert.equal(el.scrollTop, el.scrollHeight)
  assert.equal(context.followLatest, true)

  context.runNext()
  assert.ok(!incoming[1].hasAttribute("data-reveal-pending"))
  assert.ok(incoming.slice(2).every(entry => entry.hasAttribute("data-reveal-pending")))

  const clickEvent = {defaultPrevented: false, preventDefault() { this.defaultPrevented = true }}
  el.button.listeners.get("click")(clickEvent)
  assert.equal(clickEvent.defaultPrevented, true)
  assert.ok(incoming.every(entry => !entry.hasAttribute("data-reveal-pending")))
  assert.equal(context.revealQueue.length, 0)
  assert.equal(el.controls.hidden, true)
  assert.equal(el.announcement.textContent, "New story is ready.")
})

test("prepended history appears immediately and does not move the reader", () => {
  const newest = new FakeEntry(8, "gm_narration")
  const el = new FakeTimeline([newest])
  const context = createContext(el)
  context.mounted()
  el.scrollTop = 80
  context.onScroll()

  const older = new FakeEntry(3, "player_action")
  context.beforeUpdate()
  el.entries.unshift(older)
  el.scrollHeight += 240
  context.updated()

  assert.equal(context.revealQueue.length, 0)
  assert.equal(el.controls.hidden, true)
  assert.equal(el.scrollTop, 320)
  assert.ok(!older.hasAttribute("data-reveal-pending"))
})

test("reduced motion reveals new events without animation or a paced queue", () => {
  const el = new FakeTimeline([], true)
  const context = createContext(el, true)
  context.mounted()
  const incoming = [new FakeEntry(1, "gm_narration"), new FakeEntry(2, "npc_dialogue")]
  el.entries.push(...incoming)

  context.updated()

  assert.equal(context.revealQueue.length, 0)
  assert.equal(context.timerCount(), 0)
  assert.equal(el.controls.hidden, true)
  assert.ok(incoming.every(entry => !entry.hasAttribute("data-reveal-pending")))
  assert.equal(el.announcement.textContent, "New story is ready.")
})
