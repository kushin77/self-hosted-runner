import { useState, useEffect, useRef } from 'react';
import { rand } from './theme';

/**
 * useTick - Periodic tick for updating dashboard metrics
 */
export function useTick(ms: number = 2500): number {
  const [t, setT] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setT((x) => x + 1), ms);
    return () => clearInterval(id);
  }, [ms]);
  return t;
}

/**
 * useSparklineData - Maintains rolling window of metrics data
 */
export function useSparklineData(initialLength: number = 28, min: number = 60, max: number = 420) {
  const dataRef = useRef(Array.from({ length: initialLength }, () => rand(min, max)));

  const update = (newValue: number) => {
    dataRef.current = [...dataRef.current.slice(1), newValue];
  };

  return { data: dataRef.current, update };
}

/**
 * useRunnerMetrics - Simulates runner CPU/memory metrics
 */
export function useRunnerMetrics() {
  const [runners, setRunners] = useState(482);
  const [jobsPerMin, setJobsPerMin] = useState(347);
  const [cacheHitRate, setCacheHitRate] = useState(94);
  const [aiFixedToday, setAiFixedToday] = useState(7);

  const update = () => {
    setRunners((v) => Math.max(400, Math.min(580, v + rand(-8, 10))));
    setJobsPerMin((v) => Math.max(200, Math.min(500, v + rand(-15, 18))));
    setCacheHitRate((v) => Math.max(70, Math.min(99, v + rand(-2, 2))));
    setAiFixedToday((v) => Math.max(0, Math.min(20, v + rand(-1, 1))));
  };

  return { runners, jobsPerMin, cacheHitRate, aiFixedToday, update };
}

/**
 * useAnimatedValue - Smooth value transitions
 */
export function useAnimatedValue(target: number, speed: number = 0.1) {
  const [current, setCurrent] = useState(target);

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrent((prev) => {
        const diff = target - prev;
        if (Math.abs(diff) < 1) return target;
        return prev + diff * speed;
      });
    }, 50);

    return () => clearInterval(interval);
  }, [target, speed]);

  return current;
}
