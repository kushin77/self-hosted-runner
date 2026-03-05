import React, { useState } from 'react';
import { COLORS } from '../theme';

/**
 * Modal - Centered overlay dialog
 */
interface ModalProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}

export const Modal: React.FC<ModalProps> = ({ isOpen, onClose, title, children, footer }) => {
  if (!isOpen) return null;

  return (
    <>
      <div
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.5)',
          zIndex: 999,
        }}
        onClick={onClose}
        role="presentation"
      />
      <div
        style={{
          position: 'fixed',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          background: COLORS.surface,
          border: `1px solid ${COLORS.border}`,
          borderRadius: 12,
          boxShadow: '0 20px 60px rgba(0, 0, 0, 0.3)',
          maxWidth: 500,
          width: '90%',
          maxHeight: '90vh',
          overflow: 'auto',
          zIndex: 1000,
        }}
      >
        <div style={{ padding: 20 }}>
          <div
            style={{
              fontSize: 18,
              fontWeight: 800,
              color: COLORS.text,
              marginBottom: 12,
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
            }}
          >
            {title}
            <button
              onClick={onClose}
              style={{
                background: 'transparent',
                border: 'none',
                fontSize: 24,
                cursor: 'pointer',
                color: COLORS.textDim,
              }}
              aria-label="Close modal"
            >
              ✕
            </button>
          </div>
          <div style={{ marginBottom: footer ? 16 : 0 }}>{children}</div>
          {footer && (
            <div
              style={{
                borderTop: `1px solid ${COLORS.border}`,
                paddingTop: 16,
                display: 'flex',
                gap: 8,
                justifyContent: 'flex-end',
              }}
            >
              {footer}
            </div>
          )}
        </div>
      </div>
    </>
  );
};

/**
 * Toast - Notification message
 */
interface ToastProps {
  message: string;
  type?: 'info' | 'success' | 'warning' | 'error';
  onClose?: () => void;
  duration?: number;
}

export const Toast: React.FC<ToastProps> = ({ message, type = 'info', onClose, duration = 4000 }) => {
  React.useEffect(() => {
    if (duration && onClose) {
      const timer = setTimeout(onClose, duration);
      return () => clearTimeout(timer);
    }
  }, [duration, onClose]);

  const typeMap = {
    info: { bg: COLORS.accent + '20', border: COLORS.accent, icon: 'ℹ️' },
    success: { bg: COLORS.green + '20', border: COLORS.green, icon: '✓' },
    warning: { bg: COLORS.yellow + '20', border: COLORS.yellow, icon: '⚠️' },
    error: { bg: COLORS.red + '20', border: COLORS.red, icon: '✕' },
  };

  const t = typeMap[type];

  return (
    <div
      style={{
        position: 'fixed',
        bottom: 20,
        right: 20,
        background: t.bg,
        border: `2px solid ${t.border}`,
        borderRadius: 8,
        padding: '12px 16px',
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        maxWidth: 400,
        zIndex: 2000,
        animation: 'slideIn 0.3s ease',
      }}
      role="status"
      aria-live="polite"
    >
      <span style={{ fontSize: 16 }}>{t.icon}</span>
      <span style={{ flex: 1, color: COLORS.text, fontWeight: 500 }}>{message}</span>
      {onClose && (
        <button
          onClick={onClose}
          style={{
            background: 'transparent',
            border: 'none',
            color: COLORS.textDim,
            cursor: 'pointer',
            fontSize: 16,
          }}
          aria-label="Close notification"
        >
          ✕
        </button>
      )}
      <style>{`
        @keyframes slideIn {
          from { transform: translateX(400px); opacity: 0; }
          to { transform: translateX(0); opacity: 1; }
        }
      `}</style>
    </div>
  );
};

/**
 * Tooltip - Hover hint
 */
interface TooltipProps {
  text: string;
  children: React.ReactNode;
  position?: 'top' | 'bottom' | 'left' | 'right';
}

export const Tooltip: React.FC<TooltipProps> = ({ text, children, position = 'top' }) => {
  const [show, setShow] = useState(false);

  const positionMap = {
    top: { bottom: '100%', left: '50%', transform: 'translateX(-50%) translateY(-8px)' },
    bottom: { top: '100%', left: '50%', transform: 'translateX(-50%) translateY(8px)' },
    left: { right: '100%', top: '50%', transform: 'translateY(-50%) translateX(-8px)' },
    right: { left: '100%', top: '50%', transform: 'translateY(-50%) translateX(8px)' },
  };

  return (
    <div style={{ position: 'relative', display: 'inline-block' }}>
      <div
        onMouseEnter={() => setShow(true)}
        onMouseLeave={() => setShow(false)}
      >
        {children}
      </div>
      {show && (
        <div
          style={{
            position: 'absolute',
            background: COLORS.text,
            color: COLORS.surface,
            padding: '6px 10px',
            borderRadius: 6,
            fontSize: 11,
            fontWeight: 600,
            whiteSpace: 'nowrap',
            pointerEvents: 'none',
            zIndex: 1000,
            ...positionMap[position],
          } as React.CSSProperties}
        >
          {text}
        </div>
      )}
    </div>
  );
};

/**
 * Tabs - Tabbed interface
 */
interface TabsProps {
  tabs: Array<{ id: string; label: string; icon?: string; content: React.ReactNode }>;
  defaultTab?: string;
}

export const Tabs: React.FC<TabsProps> = ({ tabs, defaultTab }) => {
  const [active, setActive] = useState(defaultTab || tabs[0]?.id);

  return (
    <div>
      <div style={{ display: 'flex', borderBottom: `2px solid ${COLORS.border}`, gap: 0 }}>
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActive(tab.id)}
            style={{
              background: 'transparent',
              border: 'none',
              color: active === tab.id ? COLORS.accent : COLORS.textDim,
              borderBottom: active === tab.id ? `3px solid ${COLORS.accent}` : 'none',
              padding: '12px 16px',
              fontSize: 13,
              fontWeight: active === tab.id ? 700 : 400,
              cursor: 'pointer',
              transition: 'all 200ms ease',
            }}
            aria-selected={active === tab.id}
          >
            {tab.icon && <span style={{ marginRight: 6 }}>{tab.icon}</span>}
            {tab.label}
          </button>
        ))}
      </div>
      <div style={{ padding: '16px 0' }}>
        {tabs.find((t) => t.id === active)?.content}
      </div>
    </div>
  );
};

/**
 * Drawer - Side panel
 */
interface DrawerProps {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  position?: 'left' | 'right';
}

export const Drawer: React.FC<DrawerProps> = ({ isOpen, onClose, title, children, position = 'right' }) => {
  if (!isOpen) return null;

  return (
    <>
      <div
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(0, 0, 0, 0.3)',
          zIndex: 999,
        }}
        onClick={onClose}
        role="presentation"
      />
      <div
        style={{
          position: 'fixed',
          top: 0,
          [position]: 0,
          height: '100%',
          width: 320,
          background: COLORS.surface,
          borderLeft: position === 'right' ? `1px solid ${COLORS.border}` : 'none',
          borderRight: position === 'left' ? `1px solid ${COLORS.border}` : 'none',
          boxShadow: '0 10px 40px rgba(0, 0, 0, 0.2)',
          zIndex: 1000,
          overflow: 'auto',
          animation: `slideInDrawer${position === 'left' ? 'Left' : 'Right'} 0.3s ease`,
        }}
      >
        <div style={{ padding: 20 }}>
          <div
            style={{
              fontSize: 18,
              fontWeight: 800,
              color: COLORS.text,
              marginBottom: 20,
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
            }}
          >
            {title}
            <button
              onClick={onClose}
              style={{
                background: 'transparent',
                border: 'none',
                fontSize: 24,
                cursor: 'pointer',
                color: COLORS.textDim,
              }}
              aria-label="Close drawer"
            >
              ✕
            </button>
          </div>
          {children}
        </div>
        <style>{`
          @keyframes slideInDrawerLeft {
            from { transform: translateX(-100%); }
            to { transform: translateX(0); }
          }
          @keyframes slideInDrawerRight {
            from { transform: translateX(100%); }
            to { transform: translateX(0); }
          }
        `}</style>
      </div>
    </>
  );
};

/**
 * Tooltip component export
 */
export { Tooltip as Hint };
