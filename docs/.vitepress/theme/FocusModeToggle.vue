<script setup>
import DefaultTheme from 'vitepress/theme'
import { onMounted, ref } from 'vue'

const { Layout } = DefaultTheme
const enabled = ref(false)

function applyFocusMode(value) {
  enabled.value = value
  document.documentElement.classList.toggle('focus-mode', value)
  localStorage.setItem('vitepress-focus-mode', value ? '1' : '0')
}

function toggleFocusMode() {
  applyFocusMode(!enabled.value)
}

onMounted(() => {
  applyFocusMode(localStorage.getItem('vitepress-focus-mode') === '1')
})
</script>

<template>
  <Layout>
    <template #layout-bottom>
      <button
        class="focus-mode-toggle"
        type="button"
        :aria-pressed="enabled"
        :title="enabled ? '退出专注模式' : '进入专注模式'"
        @click="toggleFocusMode"
      >
        <span class="focus-mode-toggle__icon" aria-hidden="true">
          {{ enabled ? '↔' : '↕' }}
        </span>
        <span class="focus-mode-toggle__text">
          {{ enabled ? '退出专注' : '专注模式' }}
        </span>
      </button>
    </template>
  </Layout>
</template>
