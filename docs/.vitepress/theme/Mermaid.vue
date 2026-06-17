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
const closeButton = ref(null)
const lightboxScroll = ref(null)
const lightboxDiagram = ref(null)
const decodedCode = computed(() => decodeURIComponent(props.code))
const renderedSvg = ref('')
const lightboxSvg = ref('')
const lightboxOpen = ref(false)
const isDragging = ref(false)
const diagramWidth = ref(0)
const diagramHeight = ref(0)
const zoom = ref(1)
const panX = ref(0)
const panY = ref(0)
const diagramStyle = computed(() => {
  if (!diagramWidth.value || !diagramHeight.value) {
    return {}
  }

  return {
    width: `${diagramWidth.value}px`,
    height: `${diagramHeight.value}px`,
    left: `calc(50% + ${panX.value}px)`,
    top: `calc(50% + ${panY.value}px)`,
    transform: `translate(-50%, -50%) scale(${zoom.value})`,
  }
})

let renderId = 0
let mermaid
let previousBodyOverflow = ''
let dragStartX = 0
let dragStartY = 0
let dragStartPanX = 0
let dragStartPanY = 0

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function getSvgSize(svg) {
  const viewBox = svg.viewBox?.baseVal

  if (viewBox?.width && viewBox?.height) {
    return {
      width: viewBox.width,
      height: viewBox.height,
    }
  }

  const width = Number.parseFloat(svg.getAttribute('width'))
  const height = Number.parseFloat(svg.getAttribute('height'))

  if (width && height) {
    return { width, height }
  }

  const rect = svg.getBoundingClientRect()

  return {
    width: rect.width || 960,
    height: rect.height || 540,
  }
}

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
  renderedSvg.value = svg
  container.value.innerHTML = svg
}

async function openLightbox() {
  if (!renderedSvg.value || lightboxOpen.value) {
    return
  }

  const id = `mermaid-lightbox-${Date.now()}-${renderId++}`
  const { svg } = await mermaid.render(id, decodedCode.value)
  lightboxSvg.value = svg

  previousBodyOverflow = document.body.style.overflow
  document.body.style.overflow = 'hidden'
  lightboxOpen.value = true

  await nextTick()
  fitLightboxDiagram()
  closeButton.value?.focus()
}

function closeLightbox() {
  if (!lightboxOpen.value) {
    return
  }

  stopLightboxDrag()
  lightboxOpen.value = false
  lightboxSvg.value = ''
  diagramWidth.value = 0
  diagramHeight.value = 0
  zoom.value = 1
  panX.value = 0
  panY.value = 0
  document.body.style.overflow = previousBodyOverflow
}

function fitLightboxDiagram() {
  const scroll = lightboxScroll.value
  const svg = lightboxDiagram.value?.querySelector('svg')

  if (!scroll || !svg) {
    return
  }

  const size = getSvgSize(svg)
  const availableWidth = Math.max(scroll.clientWidth - 48, 320)
  const availableHeight = Math.max(scroll.clientHeight - 48, 240)
  const fitZoom = Math.min(availableWidth / size.width, availableHeight / size.height, 1)

  diagramWidth.value = size.width
  diagramHeight.value = size.height
  zoom.value = clamp(fitZoom, 0.05, 1)
  panX.value = 0
  panY.value = 0
}

function handleLightboxWheel(event) {
  if (!event.deltaY || !diagramWidth.value || !diagramHeight.value) {
    return
  }

  event.preventDefault()

  const previousZoom = zoom.value
  const nextZoom = clamp(previousZoom * (event.deltaY < 0 ? 1.12 : 0.88), 0.05, 5)

  if (nextZoom === previousZoom) {
    return
  }

  zoom.value = nextZoom
}

function startLightboxDrag(event) {
  if (event.button !== 0) {
    return
  }

  event.preventDefault()

  isDragging.value = true
  dragStartX = event.clientX
  dragStartY = event.clientY
  dragStartPanX = panX.value
  dragStartPanY = panY.value

  window.addEventListener('mousemove', handleLightboxDrag)
  window.addEventListener('mouseup', stopLightboxDrag)
}

function handleLightboxDrag(event) {
  if (!isDragging.value) {
    return
  }

  panX.value = dragStartPanX + event.clientX - dragStartX
  panY.value = dragStartPanY + event.clientY - dragStartY
}

function stopLightboxDrag() {
  if (!isDragging.value) {
    return
  }

  isDragging.value = false
  window.removeEventListener('mousemove', handleLightboxDrag)
  window.removeEventListener('mouseup', stopLightboxDrag)
}

function handleKeydown(event) {
  if (event.key === 'Escape') {
    closeLightbox()
  }
}

function handleResize() {
  if (lightboxOpen.value) {
    fitLightboxDiagram()
  }
}

onMounted(() => {
  renderDiagram()
  window.addEventListener('keydown', handleKeydown)
  window.addEventListener('resize', handleResize)
})

watch([decodedCode, isDark], async () => {
  await nextTick()
  await renderDiagram()
})

onBeforeUnmount(() => {
  if (container.value) {
    container.value.innerHTML = ''
  }
  window.removeEventListener('keydown', handleKeydown)
  window.removeEventListener('resize', handleResize)
  window.removeEventListener('mousemove', handleLightboxDrag)
  window.removeEventListener('mouseup', stopLightboxDrag)
  closeLightbox()
})
</script>

<template>
  <div class="mermaid-wrapper">
    <button
      class="mermaid-zoom-button"
      type="button"
      aria-label="放大 Mermaid 图"
      @click="openLightbox"
    >
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M15 3h6v6h-2V6.41l-5.3 5.3-1.4-1.42 5.29-5.29H15V3Z" />
        <path d="M9 21H3v-6h2v2.59l5.3-5.3 1.4 1.42-5.29 5.29H9v2Z" />
      </svg>
    </button>
    <button
      class="mermaid-diagram-button"
      type="button"
      aria-label="放大 Mermaid 图"
      @click="openLightbox"
    >
      <span ref="container" class="mermaid-diagram" />
    </button>
  </div>

  <Teleport to="body">
    <div
      v-if="lightboxOpen"
      class="mermaid-lightbox"
      role="dialog"
      aria-modal="true"
      aria-label="Mermaid 放大图"
      @click.self="closeLightbox"
    >
      <button
        ref="closeButton"
        class="mermaid-lightbox-close"
        type="button"
        aria-label="关闭 Mermaid 放大图"
        @click="closeLightbox"
      >
        <svg viewBox="0 0 24 24" aria-hidden="true">
          <path d="m6.4 5 12.6 12.6-1.4 1.4L5 6.4 6.4 5Z" />
          <path d="M17.6 5 19 6.4 6.4 19 5 17.6 17.6 5Z" />
        </svg>
      </button>
      <div ref="lightboxScroll" class="mermaid-lightbox-scroll" @wheel.prevent="handleLightboxWheel">
        <div
          class="mermaid-lightbox-stage"
          :class="{ 'is-dragging': isDragging }"
          @mousedown="startLightboxDrag"
          @dragstart.prevent
        >
          <div
            ref="lightboxDiagram"
            class="mermaid-lightbox-diagram"
            :class="{ 'is-dragging': isDragging }"
            :style="diagramStyle"
            v-html="lightboxSvg"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.mermaid-wrapper {
  position: relative;
  margin: 16px 0;
  overflow-x: auto;
}

.mermaid-diagram-button {
  display: block;
  width: 100%;
  min-width: 320px;
  padding: 0;
  border: 0;
  background: transparent;
  cursor: zoom-in;
}

.mermaid-diagram {
  display: block;
  min-width: 320px;
}

.mermaid-diagram :deep(svg) {
  max-width: 100%;
  height: auto;
}

.mermaid-zoom-button,
.mermaid-lightbox-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border: 1px solid var(--vp-c-divider);
  border-radius: 6px;
  color: var(--vp-c-text-2);
  background: var(--vp-c-bg-soft);
  cursor: pointer;
}

.mermaid-zoom-button {
  position: absolute;
  top: 8px;
  right: 8px;
  z-index: 1;
  opacity: 0;
  transition: opacity 0.2s ease, color 0.2s ease, border-color 0.2s ease;
}

.mermaid-wrapper:hover .mermaid-zoom-button,
.mermaid-zoom-button:focus-visible {
  opacity: 1;
}

.mermaid-zoom-button:hover,
.mermaid-lightbox-close:hover {
  color: var(--vp-c-brand-1);
  border-color: var(--vp-c-brand-1);
}

.mermaid-zoom-button svg,
.mermaid-lightbox-close svg {
  width: 18px;
  height: 18px;
  fill: currentColor;
}

.mermaid-lightbox {
  position: fixed;
  inset: 0;
  z-index: 9999;
  padding: 64px 24px 24px;
  background: color-mix(in srgb, var(--vp-c-bg) 90%, transparent);
}

.mermaid-lightbox-close {
  position: fixed;
  top: 18px;
  right: 18px;
  background: var(--vp-c-bg);
}

.mermaid-lightbox-scroll {
  width: 100%;
  height: 100%;
  overflow: hidden;
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  background: var(--vp-c-bg);
}

.mermaid-lightbox-stage {
  position: relative;
  width: 100%;
  height: 100%;
  cursor: grab;
  user-select: none;
}

.mermaid-lightbox-stage.is-dragging {
  cursor: grabbing;
}

.mermaid-lightbox-diagram {
  position: absolute;
  transform-origin: center center;
}

.mermaid-lightbox-diagram.is-dragging {
  pointer-events: none;
}

.mermaid-lightbox-diagram :deep(svg) {
  display: block;
  width: 100%;
  height: 100%;
  max-width: none;
}

@media (max-width: 640px) {
  .mermaid-lightbox {
    padding: 56px 12px 12px;
  }

  .mermaid-zoom-button {
    opacity: 1;
  }
}
</style>
