extends Node
## Ads wrapper. Step 6 connects this to the AdMob Android plugin.
## Until then (and on desktop/editor) ads are simulated so the flow is testable.

signal rewarded_finished(rewarded: bool)
signal interstitial_closed

const SIMULATED_AD_SECONDS := 1.0


func is_rewarded_ready() -> bool:
	return true


## Shows a rewarded ad; emits rewarded_finished(true) if the user earned the reward.
func show_rewarded() -> void:
	await get_tree().create_timer(SIMULATED_AD_SECONDS).timeout
	rewarded_finished.emit(true)


func show_interstitial() -> void:
	await get_tree().create_timer(0.1).timeout
	interstitial_closed.emit()
