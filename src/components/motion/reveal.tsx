"use client";

import { motion } from "framer-motion";

/** Choréographie d'entrée : le titre glisse, puis la nav, puis le contenu — jamais tout d'un coup. */
export function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
}) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ type: "spring", stiffness: 300, damping: 26, delay }}
      className={className}
    >
      {children}
    </motion.div>
  );
}
