import test from "node:test"
import assert from "node:assert/strict"
import {PanelPulse} from "./panel_pulse.mjs"

const fakeClassList = () => {
  const classes = new Set()
  return {
    add: value => classes.add(value),
    remove: value => classes.delete(value),
    contains: value => classes.has(value)
  }
}

const fakeElement = (key, value, state = "") => ({
  dataset: {panelWatch: key, panelWatchState: state},
  textContent: value,
  classList: fakeClassList(),
  offsetWidth: 100
})

const fakeHook = values => {
  const root = {
    dataset: {},
    querySelectorAll: selector => (selector === "[data-panel-watch]" ? values : []),
    querySelector: () => null
  }
  const hook = Object.create(PanelPulse)
  hook.el = root
  return hook
}

test("panel values pulse only when their displayed state changes", t => {
  const balance = fakeElement("balance", "12 bottles")
  const hook = fakeHook([balance])
  hook.mounted()
  t.after(() => hook.destroyed())

  hook.beforeUpdate()
  hook.updated()
  assert.equal(balance.classList.contains("board-state-changed"), false)

  hook.beforeUpdate()
  balance.textContent = "11 bottles"
  hook.updated()
  assert.equal(balance.classList.contains("board-state-changed"), true)
})

test("newly added public panel values also receive a change pulse", t => {
  const count = fakeElement("inventory-count", "1")
  const hook = fakeHook([count])
  hook.mounted()
  t.after(() => hook.destroyed())

  const newItem = fakeElement("inventory-new-item", "Amber apples 3")
  hook.beforeUpdate()
  count.textContent = "2"
  hook.el.querySelectorAll = () => [count, newItem]
  hook.updated()

  assert.equal(count.classList.contains("board-state-changed"), true)
  assert.equal(newItem.classList.contains("board-state-changed"), true)
})

test("state-only changes also pulse watched panel values", t => {
  const objective = fakeElement("objective-glasshouse", "Repair the glasshouse roof", "open")
  const hook = fakeHook([objective])
  hook.mounted()
  t.after(() => hook.destroyed())

  hook.beforeUpdate()
  objective.dataset.panelWatchState = "completed"
  hook.updated()

  assert.equal(objective.classList.contains("board-state-changed"), true)
})
