<template>
  <span class="brand-logo" :aria-label="branding.name">
    <img v-if="branding.logoUrl" :src="branding.logoUrl" :alt="branding.name" />
    <span v-else>{{ branding.name }}</span>
  </span>
</template>

<script setup lang="ts">
import branding from '@/config/branding.json'
</script>

<style scoped>
.brand-logo {
  display: inline-flex;
  align-items: center;
  max-width: 100%;
  color: var(--td-text-color-primary);
  font-size: 19px;
  font-weight: 650;
  letter-spacing: -0.7px;
  line-height: 1.5;
  white-space: nowrap;
}
.brand-logo img {
  display: block;
  width: 100%;
  max-height: 40px;
  object-fit: contain;
  object-position: left center;
}
</style>
