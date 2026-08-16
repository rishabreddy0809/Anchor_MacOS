/**
 * Generates public/sitemap.xml and keeps the Sitemap line in public/robots.txt
 * in step with it.
 *
 * SITE_URL is read out of src/lib/site.ts rather than duplicated here, so the
 * domain lives in exactly one place. Run `npm run sitemap` after changing it.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const siteTs = readFileSync(resolve(root, "src/lib/site.ts"), "utf8");
const match = siteTs.match(/export const SITE_URL = "([^"]+)"/);
if (!match) {
  console.error("Could not find SITE_URL in src/lib/site.ts");
  process.exit(1);
}
const origin = match[1].replace(/\/$/, "");

/** Every route in src/routes that should be indexed. */
const routes = [
  { path: "/", priority: "1.0", changefreq: "weekly" },
  { path: "/apply", priority: "0.9", changefreq: "monthly" },
  { path: "/privacy", priority: "0.5", changefreq: "yearly" },
  { path: "/terms", priority: "0.5", changefreq: "yearly" },
  { path: "/pilot-terms", priority: "0.5", changefreq: "yearly" },
  { path: "/support", priority: "0.5", changefreq: "yearly" },
];

const today = new Date().toISOString().slice(0, 10);

const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${routes
  .map(
    (r) => `  <url>
    <loc>${origin}${r.path}</loc>
    <lastmod>${today}</lastmod>
    <changefreq>${r.changefreq}</changefreq>
    <priority>${r.priority}</priority>
  </url>`,
  )
  .join("\n")}
</urlset>
`;

writeFileSync(resolve(root, "public/sitemap.xml"), xml);

const robotsPath = resolve(root, "public/robots.txt");
const robots = readFileSync(robotsPath, "utf8").replace(
  /^Sitemap: .*$/m,
  `Sitemap: ${origin}/sitemap.xml`,
);
writeFileSync(robotsPath, robots);

console.log(`sitemap.xml written for ${origin} (${routes.length} urls)`);
