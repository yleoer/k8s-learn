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
  const match = name.match(/^(\d+-\d+)-(.+)\.md$/)

  if (!match) {
    return null
  }

  return {
    no: match[1],
    title: match[2],
    dur: '',
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
          const [aChapter, aLesson] = a.no.split('-').map(Number)
          const [bChapter, bLesson] = b.no.split('-').map(Number)

          return aChapter - bChapter || aLesson - bLesson
        })

      return {
        ...chapter,
        lessons,
      }
    })
}

const course = readCourseFromDocs()

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const courseParts = [
  { text: '入门起步', label: '一 · 入门起步', from: 1, to: 1, flat: true },
  { text: '容器基石', label: '二 · 容器基石', from: 2, to: 9 },
  { text: 'K8s 核心', label: '三 · K8s 核心资源', from: 10, to: 17 },
  { text: '综合实战', label: '四 · 综合实战', from: 18, to: 19 },
  { text: '调度治理', label: '五 · 调度与资源治理', from: 20, to: 25 },
  { text: '工程弹性', label: '六 · 工程化与弹性', from: 26, to: 28 },
  { text: '可观测性', label: '七 · 可观测性', from: 29, to: 33 },
  { text: '分布式存储', label: '八 · 分布式存储', from: 34, to: 34 },
  { text: 'DevOps', label: '九 · DevOps 落地', from: 35, to: 38 },
  { text: '企业落地', label: '十 · 企业级落地', from: 39, to: 43 },
]

const courseChapters = course.map((chapter, index) => {
  const dir = chapterPath(chapter, index)
  const num = chapter.num ?? String(index + 1).padStart(2, '0')

  return {
    ...chapter,
    dir,
    num,
    number: Number.parseInt(num, 10),
    link: `/${dir}/`,
    items: chapter.lessons.map((lesson) => ({
      text: `${lesson.no} ${lesson.title}`,
      link: `/${dir}/${lessonPath(lesson)}`,
    })),
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

function partSidebar(part) {
  if (part.flat) {
    return [
      {
        text: part.label,
        items: [
          ...chaptersInPart(part).flatMap((chapter) => chapter.items),
          { text: '附录：Docker 并行使用', link: '/01-入门起步/appendix-Docker并行使用' },
          { text: '附录：环境准备执行速查', link: '/01-入门起步/appendix-环境准备执行速查' },
        ],
      },
    ]
  }

  return [
    {
      text: part.label,
      items: chaptersInPart(part).map((chapter) => ({
        text: `${chapter.num}. ${chapter.title}`,
        link: chapter.link,
        collapsed: true,
        items: chapter.items,
      })),
    },
  ]
}

const courseSidebar = {
  '/': [
    {
      text: '课程导航',
      items: courseParts.map((part) => ({
        text: part.label,
        link: partLink(part),
      })),
    },
  ],
  ...Object.fromEntries(courseParts.flatMap((part) => {
    const sidebar = partSidebar(part)

    return chaptersInPart(part).map((chapter) => [chapter.link, sidebar])
  })),
}

const courseNav = [
  { text: '首页', link: '/' },
  ...courseParts.map((part) => ({
    text: part.text,
    link: partLink(part),
    activeMatch: partActiveMatch(part),
  })),
]

// VitePress 配置文档：https://vitepress.dev/reference/site-config
export default defineConfig({
  lang: 'zh-CN',
  title: 'K8s 学习记录',
  description: '我的 Kubernetes 学习笔记与实践记录',
  lastUpdated: true,
  cleanUrls: true,
  head: [
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
      { icon: 'github', link: 'https://github.com' },
    ],
  },
})
