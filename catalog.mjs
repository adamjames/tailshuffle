#!/usr/bin/env node
/**
 * Generate a JSON catalog of all Tailwind UI components.
 * Useful for LLM context.
 */

import { readdirSync, statSync, writeFileSync } from 'fs';
import { join, relative, basename, dirname } from 'path';

const COMPONENTS_DIR = 'output/components';
const OUTPUT_FILE = 'components-catalog.json';

function walkDir(dir, fileList = []) {
  const files = readdirSync(dir);
  for (const file of files) {
    const filePath = join(dir, file);
    const stat = statSync(filePath);
    if (stat.isDirectory()) {
      walkDir(filePath, fileList);
    } else if (file.endsWith('.html')) {
      fileList.push(filePath);
    }
  }
  return fileList;
}

function buildCatalog(files) {
  const catalog = {
    _meta: {
      generated: new Date().toISOString(),
      totalComponents: files.length,
      source: COMPONENTS_DIR
    }
  };

  for (const file of files) {
    const relPath = relative(COMPONENTS_DIR, file);
    const parts = relPath.split('/');
    const componentName = basename(parts.pop(), '.html');

    // Navigate/create nested structure
    let current = catalog;
    for (const part of parts) {
      if (!current[part]) {
        current[part] = {};
      }
      current = current[part];
    }

    // Add component to array at leaf level
    if (!current._components) {
      current._components = [];
    }
    current._components.push(componentName);
  }

  return catalog;
}

function cleanupCatalog(obj) {
  // Convert _components arrays and clean up structure
  const result = {};

  for (const [key, value] of Object.entries(obj)) {
    if (key === '_meta') {
      result[key] = value;
    } else if (key === '_components') {
      // Skip, will be handled by parent
    } else if (typeof value === 'object' && value !== null) {
      if (value._components && Object.keys(value).length === 1) {
        // Leaf node with only components
        result[key] = value._components.sort();
      } else {
        // Has nested structure
        const cleaned = cleanupCatalog(value);
        if (value._components) {
          cleaned._components = value._components.sort();
        }
        result[key] = cleaned;
      }
    }
  }

  return result;
}

// Main
console.log(`Scanning ${COMPONENTS_DIR}...`);
const files = walkDir(COMPONENTS_DIR);
console.log(`Found ${files.length} components`);

const catalog = buildCatalog(files);
const cleanedCatalog = cleanupCatalog(catalog);

// Also create a flat list for easy reference
cleanedCatalog._flat = files.map(f => relative(COMPONENTS_DIR, f).replace('.html', '')).sort();

// Category summary
const categories = {};
for (const file of files) {
  const relPath = relative(COMPONENTS_DIR, file);
  const category = relPath.split('/')[0];
  categories[category] = (categories[category] || 0) + 1;
}
cleanedCatalog._meta.categories = categories;

writeFileSync(OUTPUT_FILE, JSON.stringify(cleanedCatalog, null, 2));
console.log(`Written to ${OUTPUT_FILE}`);
console.log('\nCategory breakdown:');
for (const [cat, count] of Object.entries(categories).sort()) {
  console.log(`  ${cat}: ${count} components`);
}
