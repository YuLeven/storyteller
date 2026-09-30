export const ActionComposer = {
  mounted() {
    this.handleEvent("action-composer:update", ({draft}) => {
      this.el.value = draft

      if (!this.el.disabled) {
        this.el.focus()
        this.el.setSelectionRange(this.el.value.length, this.el.value.length)
      }
    })
  }
}
