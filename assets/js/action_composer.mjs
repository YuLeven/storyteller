export const ActionComposer = {
  mounted() {
    this.onKeydown = event => {
      if (
        event.key !== "Enter" ||
        !(event.ctrlKey || event.metaKey) ||
        event.isComposing ||
        this.el.disabled
      ) {
        return
      }

      event.preventDefault()
      this.el.form?.requestSubmit()
    }

    this.el.addEventListener("keydown", this.onKeydown)

    this.handleEvent("action-composer:update", ({draft}) => {
      this.el.value = draft

      if (!this.el.disabled) {
        this.el.focus()
        this.el.setSelectionRange(this.el.value.length, this.el.value.length)
      }
    })
  },

  destroyed() {
    this.el.removeEventListener("keydown", this.onKeydown)
  }
}
