import test from "node:test"
import assert from "node:assert/strict"
import {ActionComposer} from "./action_composer.mjs"

const fakeInput = () => ({
  value: "",
  textContent: "",
  disabled: false,
  focused: false,
  selection: null,
  form: {
    submissions: 0,
    requestSubmit() {
      this.submissions += 1
    }
  },
  listeners: new Map(),
  eventHandlers: new Map(),
  addEventListener(event, handler) {
    this.listeners.set(event, handler)
  },
  removeEventListener(event, handler) {
    if (this.listeners.get(event) === handler) this.listeners.delete(event)
  },
  focus() {
    this.focused = true
  },
  setSelectionRange(start, end) {
    this.selection = [start, end]
  }
})

const fakeHook = input => {
  const hook = Object.create(ActionComposer)
  hook.el = input
  hook.handleEvent = (event, handler) => hook.el.eventHandlers.set(event, handler)
  return hook
}

const compose = (hook, draft) => hook.el.eventHandlers.get("action-composer:update")({draft})

test("a server-pushed item action appears in the composer and receives focus", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()

  compose(hook, "I use Amber apples.")

  assert.equal(input.value, "I use Amber apples.")
  assert.equal(input.focused, true)
  assert.deepEqual(input.selection, [19, 19])
})

test("ordinary updates do not overwrite an unsaved draft or steal focus", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()

  input.value = "I describe another action."

  assert.equal(input.value, "I describe another action.")
  assert.equal(input.focused, false)
})

test("a later item action moves the caret to the end of the combined draft", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()

  const draft = "I check the strap.\nI use Amber apples."
  compose(hook, draft)

  assert.equal(input.value, draft)
  assert.equal(input.selection[0], input.value.length)
  assert.equal(input.selection[1], input.value.length)
})

test("a disabled composer retains the suggested action without trying to steal focus", () => {
  const input = fakeInput()
  input.disabled = true
  const hook = fakeHook(input)
  hook.mounted()

  compose(hook, "I use Amber apples.")

  assert.equal(input.value, "I use Amber apples.")
  assert.equal(input.focused, false)
})

test("Ctrl+Enter submits the action through the form", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()
  let prevented = false

  input.listeners.get("keydown")({
    key: "Enter",
    ctrlKey: true,
    metaKey: false,
    isComposing: false,
    preventDefault() { prevented = true }
  })

  assert.equal(prevented, true)
  assert.equal(input.form.submissions, 1)
})

test("plain Enter keeps its textarea newline behavior", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()
  let prevented = false

  input.listeners.get("keydown")({
    key: "Enter",
    ctrlKey: false,
    metaKey: false,
    isComposing: false,
    preventDefault() { prevented = true }
  })

  assert.equal(prevented, false)
  assert.equal(input.form.submissions, 0)
})

test("the hook removes its keyboard listener when destroyed", () => {
  const input = fakeInput()
  const hook = fakeHook(input)
  hook.mounted()

  hook.destroyed()

  assert.equal(input.listeners.has("keydown"), false)
})
