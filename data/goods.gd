extends RefCounted
## The cargoes. To add one, copy a line and change it.
##   origin      the port that sells it (an id from data/ports.gd)
##   perishable  true: worth more after a fast passage, less after a slow one
##   buy         price per unit at the origin
##   wanted_at   ports that pay extra for it (never its own origin)

const GOODS := {
	"newspapers": {"name": "Newspapers", "origin": "melbourne", "perishable": true, "buy": 8, "wanted_at": ["geelong", "queenscliff"]},
	"tools": {"name": "Tools", "origin": "melbourne", "perishable": false, "buy": 10, "wanted_at": ["geelong", "barwon"]},
	"butter": {"name": "Butter", "origin": "geelong", "perishable": true, "buy": 9, "wanted_at": ["melbourne"]},
	"wool": {"name": "Wool", "origin": "geelong", "perishable": false, "buy": 10, "wanted_at": ["melbourne"]},
	"fish": {"name": "Fresh fish", "origin": "queenscliff", "perishable": true, "buy": 8, "wanted_at": ["melbourne", "geelong"]},
	"lime": {"name": "Lime", "origin": "queenscliff", "perishable": false, "buy": 10, "wanted_at": ["melbourne", "geelong"]},
	"fruit": {"name": "Fruit", "origin": "mornington", "perishable": true, "buy": 9, "wanted_at": ["melbourne", "queenscliff"]},
	"timber": {"name": "Timber", "origin": "mornington", "perishable": false, "buy": 10, "wanted_at": ["melbourne", "geelong"]},
	"crayfish": {"name": "Crayfish", "origin": "barwon", "perishable": true, "buy": 9, "wanted_at": ["melbourne"]},
	"onions": {"name": "Onions", "origin": "barwon", "perishable": false, "buy": 10, "wanted_at": ["melbourne", "mornington"]},
}
