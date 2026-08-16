# Anchor: See Students Clearly

I want you to make a landing page, that is super, PROJECT: Anchor Landing Page - Premium Apple/DJI Aesthetic

ABOUT ANCHOR:
Anchor is a macOS app that helps teachers identify struggling students in real-time during Zoom classes. It uses:
- Real-time behavioral signals (who's muted, speaking, camera status)
- Google Classroom integration (assignment data, grades)
- Core ML machine learning model (97% accuracy)
- Apple Foundation Models (AI-powered recommendations)

TARGET: Online teachers who teach via Zoom. Free pilots program.

DESIGN AESTHETIC:
- Apple-like (clean, minimal, lots of whitespace)
- DJI-like (smooth animations, premium feel)
- Dark hero section with light text, then white sections below
- Smooth scroll animations
- Professional, not flashy

REQUIREMENTS:

1. HERO SECTION
   - Dark background (charcoal #1A1A1A or pure black)
   - Large headline: "See what your students aren't saying."
   - Subheadline: "Anchor detects struggling students in real-time during Zoom classes."
   - CTA Button: "Join Pilot Program" (bright accent color - suggest blue or teal)
   - Below text: WebGL animated visualization of student engagement
   
   WebGL Visualization:
   - Particle system showing ~100 particles
   - Red particles = struggling students (clustered, slow movement)
   - Green particles = engaged students (spread out, fast movement)
   - Particles float smoothly, no jerky movement
   - On hover: particle expands, shows engagement level
   - Optional: subtle mouse-tracking effect (particles follow cursor slightly)
   - Smooth, mesmerizing, not distracting
   - Falls back to static image if WebGL unavailable

2. NAVIGATION
   - Sticky header at top
   - Anchor logo (text "Anchor")
   - Links: [Home] [How It Works] [Pilots] [Contact]
   - Right side: CTA button "Get Started"
   - White text on dark background

3. SECTION 1: THE PROBLEM
   Background: White
   - Headline: "The challenge of online teaching"
   - Text: "40% of online students go silent during class. Teachers don't know until grades drop. By then, it's often too late."
   - Screenshot: Your actual Anchor dashboard showing a struggling student (red card)
   - Fade-in animation as user scrolls into view

4. SECTION 2: THE SOLUTION
   Background: White
   - Headline: "Real-time struggle detection"
   - Subtext: "Anchor monitors behavioral signals to identify at-risk students instantly"
   - 3 signal cards:
     * "Speaking Time" [icon] "Who's engaging?"
     * "Camera Status" [icon] "Who's present?"
     * "Assignment Data" [icon] "Who's falling behind?"
   - Large screenshot: Dashboard showing multiple students ranked by struggle score
   - Parallax scroll effect (image moves slower than text)

5. SECTION 3: TEACHER IMPACT
   Background: Light gray (#F9F9F9)
   - Headline: "Teachers love it"
   - Testimonial card (animated on scroll):
     * Quote: "I caught Sarah's struggle 2 weeks before her grades dropped."
     * Author: "Ms. Johnson, Online School Teacher"
     * Star rating (5 stars)
   - Stats (counters animate on scroll):
     * "87% of teachers identify at-risk students earlier"
     * "2-week average early warning"
     * "100% recommended by pilots"

6. SECTION 4: HOW IT WORKS
   Background: White
   - Headline: "3 simple steps"
   - Step 1: "Connect your Zoom account" [Icon/screenshot]
   - Step 2: "Go live with a class" [Icon/screenshot]
   - Step 3: "Anchor detects struggling students" [Icon/screenshot]
   - Timeline animation: Numbers animate as you scroll

7. SECTION 5: FEATURES
   Background: White
   - Headline: "Built for teachers"
   - 3 feature cards (grid layout, hover effects):
     * Feature 1: "Real-time Detection"
       Description: "See struggle indicators as class happens"
       Screenshot: Dashboard view
     * Feature 2: "Classroom Integration"
       Description: "Combine Zoom signals with assignment data"
       Screenshot: Settings/integration view
     * Feature 3: "AI Recommendations"
       Description: "Actionable next steps powered by AI"
       Screenshot: Student detail with recommendations

8. SECTION 6: PRIVACY & SECURITY
   Background: Light gray
   - Headline: "Privacy first"
   - 3 trust cards:
     * "No facial recognition" [Icon]
     * "On-device ML processing" [Icon]
     * "Your data stays yours" [Icon]
   - Text: "Built with teacher privacy in mind. No surveillance. No data selling."

9. SECTION 7: PRICING / PILOTS
   Background: White
   - Headline: "Currently accepting pilots"
   - Card: 
     * "Free pilot access"
     * "Full feature set"
     * "Direct teacher support"
     * "Shape the product"
     * [CTA Button: "Join Now"]

10. SECTION 8: CTA
    Background: Dark (matching hero)
    - Headline: "Ready to support your students?"
    - Subheadline: "Join the pilot program and transform how you teach online."
    - Large CTA Button: "Get Started Today"
    - Secondary text: "Questions? Email anchor@yourdomain.com"

11. FOOTER
    Background: Black
    - Logo
    - Links: [About] [Contact] [Privacy] [Terms]
    - Social: [LinkedIn] [Twitter]
    - Copyright

ANIMATIONS:
- All scroll-triggered (use Intersection Observer)
- Fade-in effects (opacity 0 → 1)
- Slide-in from sides (translateX)
- Parallax scroll (images move at different speeds)
- Hover effects on buttons/cards (scale, color change)
- Counter animations (0 → number)
- Smooth scroll behavior (not instant jumps)

COLORS:
- Primary Background: White (#FFFFFF)
- Dark sections: #1A1A1A or #0A0A0A
- Accent color: Teal (#00D9FF) or Blue (#0066FF) - pick one
- Text: Dark gray (#1A1A1A)
- Secondary text: Medium gray (#666666)
- Borders: Light gray (#EEEEEE)

TYPOGRAPHY:
- Headlines: Bold, 48-64px, Inter or Poppins
- Body: Regular, 16-18px, Inter or system font
- Line height: 1.6
- Letter spacing: Normal to slightly loose

IMAGES/MEDIA:
- Hero: WebGL particle animation (see section 1)
- Screenshots: Real Anchor app screenshots (I'll provide or you describe)
- Icons: Simple, minimal, SVG
- Video: Optional 30-60 second loop of dashboard (muted)

RESPONSIVE:
- Desktop (1200px+): Full animations, side-by-side layouts
- Tablet (768-1199px): Stack layouts, simplified animations
- Mobile (under 768px): Full-width, minimal animations, touch-friendly buttons (44px+)

PERFORMANCE:
- Fast load time (Lighthouse 90+)
- Optimize images (WebP)
- Lazy load below-fold content
- Smooth 60fps scrolling

BUILD COMPLETELY:
1. Hero with WebGL particle system
2. All sections (8 total)
3. Smooth scroll animations
4. Responsive design
5. Navigation
6. Footer
7. Mobile optimized
8. Fast performance
9. Production ready

DEPLOY TO:
- GitHub Pages or Vercel (free)
- Use custom domain if available

This should be a portfolio-quality landing page that converts pilots and looks professional. The WebGL particle system is the "wow" element, but the real value is in communicating what Anchor does.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/bb0ba5f9-4184-4110-893f-22d7efb27cde).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
