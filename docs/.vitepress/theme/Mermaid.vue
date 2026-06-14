<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useData } from 'vitepress'

const props = defineProps({
  code: {
    type: String,
    required: true,
  },
})

const { isDark } = useData()
const container = ref(null)
const decodedCode = computed(() => decodeURIComponent(props.code))

let renderId = 0
let mermaid

async function renderDiagram() {
  if (!container.value) {
    return
  }

  if (!mermaid) {
    mermaid = (await import('mermaid')).default
  }

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: isDark.value ? 'dark' : 'default',
  })

  const id = `mermaid-${Date.now()}-${renderId++}`
  const { svg } = await mermaid.render(id, decodedCode.value)
  container.value.innerHTML = svg
}

onMounted(renderDiagram)

watch([decodedCode, isDark], async () => {
  await nextTick()
  await renderDiagram()
})

onBeforeUnmount(() => {
  if (container.value) {
    container.value.innerHTML = ''
  }
})
</script>

<template>
  <div class="mermaid-wrapper">
    <div ref="container" class="mermaid-diagram" />
  </div>
</template>

<style scoped>
.mermaid-wrapper {
  margin: 16px 0;
  overflow-x: auto;
}

.mermaid-diagram {
  min-width: 320px;
}

.mermaid-diagram :deep(svg) {
  max-width: 100%;
  height: auto;
}
</style>
