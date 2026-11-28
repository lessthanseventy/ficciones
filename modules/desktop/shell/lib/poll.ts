// ags's createPoll drops a rejection on the floor (an unhandled one, every tick); every poll of
// ours goes through this one, which keeps the last value.
import { createPoll as poll } from "ags/time"
import { kept } from "./poll-core"

export const createPoll = <T,>(init: T, ms: number, fn: (prev: T) => T | Promise<T>) => poll(init, ms, kept(fn))
