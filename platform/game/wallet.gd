class_name Wallet
extends RefCounted
## A game currency (mana, coins, gold): balance, earning with a multiplier,
## spending with a markup, refunds, and a transaction log for tests and
## balance tools. Amounts are whole numbers.
##
##   earn(base, reason)      adds round(base x earn_multiplier)
##   price(base)             what something costs now: ceil(base x markup)
##   spend(base, reason)     pays price(base) if affordable (false otherwise)
##   refund(amount, reason)  adds amount as-is (no multiplier)

signal changed(balance: int, delta: int, reason: StringName)

var balance: int = 0
## Applied to earn() (e.g. an Autostart streak). 1.0 = none.
var earn_multiplier: float = 1.0
## Applied to price() / spend() (e.g. the mid-wave markup). 1.0 = none.
var markup: float = 1.0
var total_earned: int = 0
var total_spent: int = 0
## Every change: {delta, reason, balance}. Capped to the last LOG_MAX.
var log: Array[Dictionary] = []
const LOG_MAX: int = 256


func _init(start: int = 0) -> void:
	balance = maxi(0, start)


func reset(start: int) -> void:
	balance = maxi(0, start)
	total_earned = 0
	total_spent = 0
	earn_multiplier = 1.0
	markup = 1.0
	log.clear()
	changed.emit(balance, 0, &"reset")


static func price_with(base: int, p_markup: float) -> int:
	return int(ceil(base * p_markup - 0.0001))


func price(base: int) -> int:
	return price_with(base, markup)


func can_afford(base: int) -> bool:
	return balance >= price(base)


func earn(base: int, reason: StringName = &"") -> int:
	if base <= 0:
		return 0
	var amount: int = int(round(base * earn_multiplier))
	_apply(amount, reason)
	total_earned += amount
	return amount


func spend(base: int, reason: StringName = &"") -> bool:
	var cost: int = price(base)
	if cost > balance:
		return false
	_apply(-cost, reason)
	total_spent += cost
	return true


## Pay an exact amount (no markup).
func spend_exact(amount: int, reason: StringName = &"") -> bool:
	if amount > balance:
		return false
	_apply(-amount, reason)
	total_spent += amount
	return true


func refund(amount: int, reason: StringName = &"refund") -> void:
	if amount > 0:
		_apply(amount, reason)


func _apply(delta: int, reason: StringName) -> void:
	balance += delta
	log.append({"delta": delta, "reason": reason, "balance": balance})
	if log.size() > LOG_MAX:
		log.pop_front()
	changed.emit(balance, delta, reason)


## Save shape (platform-accounts doc 3.8): balance and totals; the log and
## the (situational) multiplier / markup are not saved.
func to_save() -> Dictionary:
	return {"balance": balance, "total_earned": total_earned, "total_spent": total_spent}


static func from_save(d: Dictionary) -> Wallet:
	var w := Wallet.new(int(d.get("balance", 0)))
	w.total_earned = int(d.get("total_earned", 0))
	w.total_spent = int(d.get("total_spent", 0))
	return w
