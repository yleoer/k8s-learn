import DefaultTheme from 'vitepress/theme'
import Mermaid from './Mermaid.vue'
import FocusModeToggle from './FocusModeToggle.vue'
import './style.css'

export default {
  extends: DefaultTheme,
  Layout: FocusModeToggle,
  enhanceApp({ app }) {
    app.component('Mermaid', Mermaid)
  },
}
