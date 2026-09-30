import test from "node:test"
import assert from "node:assert/strict"
import {ActionComposer} from "./action_composer.mjs"

const fakeInput = () => ({
  value: "",
  textContent: "",
  disabled: false,
  focused: false,
  selection: null,
  eventHandlers: new Map(),
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
