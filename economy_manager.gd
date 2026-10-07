class_name EconomyManager
extends Node


# ==================================================
# STARTING ECONOMY
# ==================================================

const STARTING_CASH: int = 25000


# ==================================================
# DEVELOPMENT COSTS
# ==================================================

const TEE_INSTALL_COST: int = 150
const BASKET_INSTALL_COST: int = 450

const SMALL_TREE_REMOVAL_COST: int = 75
const MEDIUM_TREE_REMOVAL_COST: int = 150
const LARGE_TREE_REMOVAL_COST: int = 300

const LAND_CLEAR_COST: int = 25


# ==================================================
# MONEY
# ==================================================

var cash: int = STARTING_CASH

var total_spent: int = 0
var total_earned: int = 0


# ==================================================
# EQUIPMENT INVENTORY
# ==================================================

var tee_inventory: int = 0
var basket_inventory: int = 0


# ==================================================
# SETUP
# ==================================================

func setup() -> void:

	reset_economy()


# ==================================================
# RESET ECONOMY
# ==================================================

func reset_economy() -> void:

	cash = STARTING_CASH

	total_spent = 0
	total_earned = 0

	tee_inventory = 0
	basket_inventory = 0


# ==================================================
# CAN AFFORD?
# ==================================================

func can_afford(
	amount: int
) -> bool:

	return cash >= amount


# ==================================================
# SPEND MONEY
# ==================================================

func spend(
	amount: int
) -> bool:

	if amount <= 0:
		return true


	if not can_afford(
		amount
	):
		return false


	cash -= amount

	total_spent += amount

	return true


# ==================================================
# EARN MONEY
# ==================================================

func earn(
	amount: int
) -> void:

	if amount <= 0:
		return


	cash += amount

	total_earned += amount


# ==================================================
# ACQUIRE TEE
# ==================================================

func acquire_tee_for_placement() -> bool:

	if tee_inventory > 0:

		tee_inventory -= 1

		return true


	if not spend(
		TEE_INSTALL_COST
	):
		return false


	return true


# ==================================================
# ACQUIRE BASKET
# ==================================================

func acquire_basket_for_placement() -> bool:

	if basket_inventory > 0:

		basket_inventory -= 1

		return true


	if not spend(
		BASKET_INSTALL_COST
	):
		return false


	return true


# ==================================================
# RETURN EQUIPMENT
# ==================================================

func return_tee_to_inventory() -> void:

	tee_inventory += 1


func return_basket_to_inventory() -> void:

	basket_inventory += 1


# ==================================================
# GET CASH
# ==================================================

func get_cash() -> int:

	return cash


# ==================================================
# GET INVENTORY
# ==================================================

func get_tee_inventory() -> int:

	return tee_inventory


func get_basket_inventory() -> int:

	return basket_inventory


# ==================================================
# GET TOTALS
# ==================================================

func get_total_spent() -> int:

	return total_spent


func get_total_earned() -> int:

	return total_earned


# ==================================================
# COST GETTERS
# ==================================================

func get_tee_install_cost() -> int:

	return TEE_INSTALL_COST


func get_basket_install_cost() -> int:

	return BASKET_INSTALL_COST


func get_tree_removal_cost(
	tree_scale: float
) -> int:

	if tree_scale < 0.85:

		return SMALL_TREE_REMOVAL_COST


	if tree_scale < 1.2:

		return MEDIUM_TREE_REMOVAL_COST


	return LARGE_TREE_REMOVAL_COST


func get_land_clear_cost() -> int:

	return LAND_CLEAR_COST


# ==================================================
# MONEY DISPLAY
# ==================================================

func format_money(
	amount: int
) -> String:

	var amount_string: String = str(
		abs(amount)
	)

	var formatted: String = ""

	var digit_count: int = 0


	for i in range(
		amount_string.length() - 1,
		-1,
		-1
	):

		if (
			digit_count > 0
			and digit_count % 3 == 0
		):

			formatted = "," + formatted


		formatted = (
			amount_string[i]
			+ formatted
		)

		digit_count += 1


	if amount < 0:

		formatted = "-" + formatted


	return "$" + formatted