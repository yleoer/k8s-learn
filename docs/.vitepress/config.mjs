import { defineConfig } from 'vitepress'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { readdirSync } from 'node:fs'

const configDir = dirname(fileURLToPath(import.meta.url))
const projectRoot = resolve(configDir, '../..')
const docsRoot = resolve(projectRoot, 'docs')

function sanitizeSegment(value) {
  return String(value || '')
    .normalize('NFKC')
    .replace(/[<>:"/\\|?*\u0000-\u001F]/g, '-')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80) || 'untitled'
}

function chapterPath(chapter, index) {
  const num = chapter.num ?? String(index + 1).padStart(2, '0')
  return `${num}-${sanitizeSegment(chapter.title)}`
}

function lessonPath(lesson) {
  return `${sanitizeSegment(lesson.no)}-${sanitizeSegment(lesson.title)}`
}

function parseChapterDir(name) {
  const match = name.match(/^(\d+)-(.+)$/)

  if (!match) {
    return null
  }

  return {
    num: match[1],
    title: match[2],
  }
}

function parseLessonFile(name) {
  const match = name.match(/^(\d+)-(.+)\.md$/)

  if (!match) {
    return null
  }

  return {
    no: match[1],
    title: match[2],
    dur: '',
  }
}

function parseAppendixFile(name) {
  const match = name.match(/^appendix-(.+)\.md$/)

  if (!match) {
    return null
  }

  return {
    text: `附录：${match[1]}`,
    linkName: `appendix-${match[1]}`,
    order: name,
  }
}

function readCourseFromDocs() {
  return readdirSync(docsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => parseChapterDir(entry.name))
    .filter(Boolean)
    .sort((a, b) => Number(a.num) - Number(b.num))
    .map((chapter) => {
      const chapterDir = resolve(docsRoot, `${chapter.num}-${chapter.title}`)
      const lessons = readdirSync(chapterDir, { withFileTypes: true })
        .filter((entry) => entry.isFile())
        .map((entry) => parseLessonFile(entry.name))
        .filter(Boolean)
        .sort((a, b) => {
          return Number(a.no) - Number(b.no)
        })
      const appendixes = readdirSync(chapterDir, { withFileTypes: true })
        .filter((entry) => entry.isFile())
        .map((entry) => parseAppendixFile(entry.name))
        .filter(Boolean)
        .sort((a, b) => (a.order > b.order ? 1 : -1))

      return {
        ...chapter,
        lessons,
        appendixes,
      }
    })
}

const course = readCourseFromDocs()

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const courseParts = [
  { text: '入门起步', label: '一 · 入门起步', from: 1, to: 1, flat: true },
  { text: '容器基石', label: '二 · 容器基石', from: 2, to: 5 },
  { text: 'K8s 核心', label: '三 · K8s 核心资源', from: 6, to: 17 },
  { text: '综合实战', label: '四 · 综合实战', from: 18, to: 19 },
  { text: '调度治理', label: '五 · 调度与资源治理', from: 20, to: 25 },
  { text: '工程弹性', label: '六 · 工程化与弹性', from: 26, to: 28 },
  { text: '可观测性', label: '七 · 可观测性', from: 29, to: 33 },
  { text: '分布式存储', label: '八 · 分布式存储', from: 34, to: 34 },
  { text: 'DevOps', label: '九 · DevOps 落地', from: 35, to: 38 },
  { text: '企业落地', label: '十 · 企业级落地', from: 39, to: 43 },
]

function customChapterItems(chapter, dir) {
  if (chapter.num !== '09' || chapter.title !== '工作负载调度') {
    return null
  }

  return [
    {
      text: 'Deployment',
      link: `/${dir}/1-Deployment`,
      collapsed: false,
      items: [
        { text: '无状态调度基础', link: `/${dir}/1-Deployment#无状态调度基础` },
        { text: 'Deployment 定义与创建', link: `/${dir}/1-Deployment#deployment-定义与创建` },
        { text: 'Deployment 更新与回滚', link: `/${dir}/1-Deployment#deployment-更新与回滚` },
        { text: 'Deployment 扩缩容与策略', link: `/${dir}/1-Deployment#deployment-扩缩容与策略` },
        { text: 'HPA 自动扩缩容', link: `/${dir}/1-Deployment#hpa-自动扩缩容` },
        { text: 'PDB 中断保护', link: `/${dir}/1-Deployment#pdb-中断保护` },
      ],
    },
    {
      text: 'StatefulSet',
      link: `/${dir}/2-StatefulSet`,
      collapsed: false,
      items: [
        { text: 'StatefulSet 基础与创建', link: `/${dir}/2-StatefulSet#statefulset-基础与创建` },
        { text: 'Headless Service 与内部通信', link: `/${dir}/2-StatefulSet#headless-service-与内部通信` },
        { text: 'StatefulSet 更新扩缩容', link: `/${dir}/2-StatefulSet#statefulset-更新扩缩容` },
      ],
    },
    {
      text: 'DaemonSet',
      link: `/${dir}/3-DaemonSet`,
      collapsed: false,
      items: [
        { text: 'DaemonSet 定义与创建', link: `/${dir}/3-DaemonSet#daemonset-定义与创建` },
        { text: 'DaemonSet 更新与节点选择', link: `/${dir}/3-DaemonSet#daemonset-更新与节点选择` },
      ],
    },
  ]
}

const courseChapters = course.map((chapter, index) => {
  const dir = chapterPath(chapter, index)
  const num = chapter.num ?? String(index + 1).padStart(2, '0')
  const defaultItems = [
    ...chapter.lessons.map((lesson) => ({
      text: lesson.title,
      link: `/${dir}/${lessonPath(lesson)}`,
    })),
    ...chapter.appendixes.map((appendix) => ({
      text: appendix.text,
      link: `/${dir}/${appendix.linkName}`,
    })),
  ]

  return {
    ...chapter,
    dir,
    num,
    number: Number.parseInt(num, 10),
    link: `/${dir}/`,
    items: customChapterItems(chapter, dir) ?? defaultItems,
  }
})

function chaptersInPart(part) {
  return courseChapters.filter((chapter) => (
    chapter.number >= part.from && chapter.number <= part.to
  ))
}

function partLink(part) {
  return chaptersInPart(part)[0]?.link ?? '/'
}

function partActiveMatch(part) {
  const chapterDirs = chaptersInPart(part).map((chapter) => escapeRegExp(chapter.dir))

  if (chapterDirs.length === 0) {
    return undefined
  }

  return `^/(${chapterDirs.join('|')})(/|$)`
}

function shortChapterTitle(title) {
  const replacements = [
    ['云原生基石-', ''],
    ['云原生基座-', ''],
    ['云原生CRI-', ''],
    ['必知必会', ''],
    ['Containerd', ''],
  ]

  return replacements.reduce(
    (value, [search, replacement]) => value.replace(search, replacement),
    title,
  )
}

function chapterSidebar(chapter, part) {
  const items = [...chapter.items]

  return [
    {
      text: chapter.title,
      link: chapter.link,
      items,
    },
  ]
}

function partNavItem(part) {
  const chapters = chaptersInPart(part)
  const activeMatch = partActiveMatch(part)

  if (chapters.length <= 1) {
    return {
      text: part.text,
      link: partLink(part),
      activeMatch,
    }
  }

  return {
    text: part.text,
    items: chapters.map((chapter) => ({
      text: shortChapterTitle(chapter.title),
      link: chapter.link,
    })),
    activeMatch,
  }
}

const visibleCourseParts = courseParts.filter((part) => chaptersInPart(part).length > 0)

const courseSidebar = {
  '/': [
    {
      text: '文档导航',
      items: visibleCourseParts.map((part) => ({
        text: part.label,
        link: partLink(part),
      })),
    },
  ],
  ...Object.fromEntries(visibleCourseParts.flatMap((part) => {
    return chaptersInPart(part).map((chapter) => [chapter.link, chapterSidebar(chapter, part)])
  })),
}

const courseNav = [
  { text: '首页', link: '/' },
  ...visibleCourseParts.map((part) => partNavItem(part)),
]

// VitePress 配置文档：https://vitepress.dev/reference/site-config
export default defineConfig({
  lang: 'zh-CN',
  title: 'Kubernetes 学习笔记',
  description: '从容器基础到 Kubernetes 集群实践的系统学习笔记',
  lastUpdated: true,
  cleanUrls: true,
  head: [
    [
      'link',
      {
        rel: 'icon',
        type: 'image/svg+xml',
        href: '/favicon.svg',
      },
    ],
    [
      'link',
      {
        rel: 'stylesheet',
        href: 'https://fonts.loli.net/css2?family=Noto+Sans+SC:wght@400;500;700&display=swap',
      },
    ],
    [
      'link',
      {
        rel: 'stylesheet',
        href: 'https://fonts.loli.net/css2?family=JetBrains+Mono:wght@400;500;700&display=swap',
      },
    ],
  ],
  markdown: {
    config(md) {
      const fence = md.renderer.rules.fence

      md.renderer.rules.fence = (tokens, idx, options, env, self) => {
        const token = tokens[idx]
        const language = token.info.trim().split(/\s+/)[0]

        if (language === 'mermaid') {
          return `<Mermaid code="${encodeURIComponent(token.content)}" />`
        }

        return fence?.(tokens, idx, options, env, self) ?? self.renderToken(tokens, idx, options)
      }
    },
  },

  themeConfig: {
    // 顶部导航
    nav: courseNav,

    // 侧边栏：从 docs 目录生成
    sidebar: courseSidebar,

    // 本地全文搜索
    search: {
      provider: 'local',
    },

    outline: {
      level: [2, 3],
      label: '本页目录',
    },

    docFooter: {
      prev: '上一篇',
      next: '下一篇',
    },

    lastUpdatedText: '最后更新',

    socialLinks: [
      { icon: 'github', link: 'https://github.com/yleoer/k8s-learn' },
    ],
  },
})
