import clsx from 'clsx';
import './logo.css';

interface LogoProps {
  size?: number;
  /** Show the wordmark alongside the icon. */
  withWordmark?: boolean;
  /** Replay the entrance animation when the prop changes. */
  animateKey?: string | number;
  /** Subtle ambient pulse — for hero placements like the login art panel. */
  ambient?: boolean;
  className?: string;
  /** Wrap in a button. */
  onClick?: () => void;
  title?: string;
}

/**
 * Bestie — premium animated brand mark.
 *
 * The mark is two stacked rounded "ribbons" inside a rounded gradient
 * container, reading as a stylized monogram. On first paint the container
 * scales in, the ribbons draw their strokes, and the corner accent dot pops
 * with a brief ping ring. On hover the gradient drifts and a glow appears.
 *
 * Sized for everything from a 16px favicon to a 128px hero. The wordmark
 * uses our brand gradient on the text fill so it stays consistent with the
 * icon. Theme-aware — the inner strokes use `currentColor` and inherit
 * `var(--c-text-invert)` over the gradient by default.
 */
export function Logo({
  size = 36,
  withWordmark = false,
  animateKey,
  ambient = false,
  className,
  onClick,
  title = 'Bestie',
}: LogoProps) {
  const inner = (
    <span
      className={clsx('lg', ambient && 'lg--ambient', className)}
      style={{ ['--lg-size' as never]: `${size}px` }}
      key={animateKey}
      role="img"
      aria-label={title}
      title={title}
    >
      <span className="lg__mark">
        <svg
          width={size}
          height={size}
          viewBox="0 0 48 48"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          aria-hidden
        >
          <defs>
            <linearGradient id="lg-bg" x1="0" y1="0" x2="48" y2="48" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stopColor="#7c5cff" />
              <stop offset="55%" stopColor="#5b8cff" />
              <stop offset="100%" stopColor="#3aa1ff" />
            </linearGradient>
            <linearGradient id="lg-bg-hover" x1="0" y1="0" x2="48" y2="48" gradientUnits="userSpaceOnUse">
              <stop offset="0%" stopColor="#5b8cff" />
              <stop offset="55%" stopColor="#7c5cff" />
              <stop offset="100%" stopColor="#e0254a" />
            </linearGradient>
          </defs>

          {/* gradient container */}
          <rect
            className="lg__bg"
            width="48" height="48" rx="12"
            fill="url(#lg-bg)"
          />
          {/* gloss highlight — top-left wash */}
          <path
            className="lg__gloss"
            d="M2 12 C 2 6, 6 2, 12 2 L 30 2 Q 22 14, 18 26 Q 10 30, 2 22 Z"
            fill="white"
            opacity="0.14"
          />

          {/* monogram ribbons — stroke-dasharrays animate them in */}
          <path
            className="lg__ribbon lg__ribbon--top"
            d="M14 13 H26 a5 5 0 0 1 0 10 H14"
            stroke="white"
            strokeWidth="3.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
          />
          <path
            className="lg__ribbon lg__ribbon--bottom"
            d="M14 23 H28 a5 5 0 0 1 0 10 H14"
            stroke="white"
            strokeWidth="3.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
          />
          <path
            className="lg__stem"
            d="M14 13 V35"
            stroke="white"
            strokeWidth="3.5"
            strokeLinecap="round"
            fill="none"
          />

          {/* accent dot + ping ring (presence / collaboration cue) */}
          <circle className="lg__ring" cx="37" cy="11" r="5" fill="none" stroke="white" strokeWidth="2" opacity="0.4" />
          <circle className="lg__dot"  cx="37" cy="11" r="3" fill="white" />
        </svg>
      </span>

      {withWordmark && (
        <span className="lg__wordmark">
          <span className="lg__word">Bestie</span>
          <span className="lg__tag">Workspace</span>
        </span>
      )}
    </span>
  );

  if (onClick) {
    return (
      <button type="button" className="lg__button m-press" onClick={onClick} aria-label={title}>
        {inner}
      </button>
    );
  }
  return inner;
}
