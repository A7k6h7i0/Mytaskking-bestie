import { useEffect, useState, ReactNode } from 'react';
import { useLocation } from 'react-router-dom';
import './page-transition.css';

interface PageTransitionProps {
  children: ReactNode;
  /** Animation variant: fade (default) | slide | scale */
  variant?: 'fade' | 'slide' | 'scale';
}

/**
 * Re-keys its children on route change so the page enters with a fresh
 * animation each time. CSS does the work — no animation library needed.
 *
 *   <PageTransition><Outlet /></PageTransition>
 */
export function PageTransition({ children, variant = 'fade' }: PageTransitionProps) {
  const location = useLocation();
  const [key, setKey] = useState(location.pathname);

  useEffect(() => {
    setKey(location.pathname);
  }, [location.pathname]);

  return (
    <div className={`pt pt--${variant}`} key={key}>
      {children}
    </div>
  );
}
