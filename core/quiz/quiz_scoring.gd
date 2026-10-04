class_name QuizScoring
extends RefCounted
## Quiz scoring and ranking (§2.9).


## Points for one answer: correct = base + round(speed × remaining / answer_time), wrong = 0.
## `elapsed` is the latency-compensated answer time in seconds.
static func points(correct: bool, elapsed: float, cfg: BalanceConfig) -> int:
	if not correct:
		return 0
	var remaining: float = clampf(cfg.quiz_answer_time - maxf(elapsed, 0.0), 0.0, cfg.quiz_answer_time)
	return cfg.quiz_base_points + int(roundf(cfg.quiz_speed_points * remaining / cfg.quiz_answer_time))


## Server-side elapsed time: receive − send − the player's smoothed half-RTT, clamped to ≥ 0.
static func compensated_elapsed(sent_at: float, received_at: float, half_rtt: float) -> float:
	return maxf(received_at - sent_at - half_rtt, 0.0)


## Ranks players: more points first; ties broken by lower cumulative correct-answer time; still
## tied → shared rank. Returns [{player, points, time, rank}] sorted best first (rank 1 = best).
static func rank(points_by_player: Dictionary, time_by_player: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for p: Variant in points_by_player:
		rows.append({"player": int(p), "points": int(points_by_player[p]), "time": float(time_by_player.get(p, 0.0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if not is_equal_approx(a["time"], b["time"]):
			return a["time"] < b["time"]
		return a["player"] < b["player"])
	for i: int in rows.size():
		if i > 0 and rows[i]["points"] == rows[i - 1]["points"] and is_equal_approx(rows[i]["time"], rows[i - 1]["time"]):
			rows[i]["rank"] = rows[i - 1]["rank"]
		else:
			rows[i]["rank"] = i + 1
	return rows
