<script setup lang="ts">
import {ref,watch} from 'vue';
export type TaskCoverData={id:number;url:string;name:string;width?:number|null;height?:number|null};
const props=defineProps<{cover?:TaskCoverData|null;large?:boolean}>();
const failed=ref(false);
watch(()=>props.cover?.url,()=>failed.value=false);
</script>
<template><div v-if="cover&&!failed" :class="['task-cover',{large}]" aria-label="Обложка задачи"><img :src="cover.url" :alt="cover.name" loading="lazy" decoding="async" draggable="false" @error="failed=true"></div></template>
<style scoped>
.task-cover{width:100%;height:156px;background:var(--side,#1b2430);border-radius:8px;overflow:hidden;margin:0 0 12px}.task-cover img{display:block;width:100%;height:100%;object-fit:contain;pointer-events:none;user-select:none}:global(.board-task)>.task-cover{width:calc(100% + 32px);margin:-19px -16px 12px;border-radius:10px 10px 0 0}.task-cover.large{height:220px;border-radius:0;margin:0;border-bottom:1px solid var(--line,#35404b);flex-shrink:0}@media(max-width:600px){.task-cover.large{height:170px}}
</style>
