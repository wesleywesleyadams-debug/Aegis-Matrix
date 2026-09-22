class_name NeuralNet
## A small fully connected network: inputs -> tanh hidden layer -> linear
## outputs (one score per action). Weights are one flat array so a trainer
## can perturb and update them as a single vector (see tools/es_train.pl).
## Layout: W1 (hidden x inputs), b1 (hidden), W2 (outputs x hidden), b2 (outputs).

var n_in: int
var n_hidden: int
var n_out: int
var w: PackedFloat32Array

func _init(inputs: int, hidden: int, outputs: int) -> void:
	n_in = inputs
	n_hidden = hidden
	n_out = outputs
	w.resize(param_count())

func param_count() -> int:
	return n_hidden * n_in + n_hidden + n_out * n_hidden + n_out

## Loads {"inputs", "hidden", "outputs", "weights": [...]}; returns null if
## the file is missing or its shape doesn't match.
static func load_json(path: String) -> NeuralNet:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not d is Dictionary:
		return null
	var net := NeuralNet.new(int(d["inputs"]), int(d["hidden"]), int(d["outputs"]))
	var ws: Array = d["weights"]
	if ws.size() != net.param_count():
		return null
	for i in ws.size():
		net.w[i] = float(ws[i])
	return net

func forward(x: PackedFloat32Array) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(n_hidden)
	var o := 0
	for j in n_hidden:
		var s := 0.0
		for i in n_in:
			s += w[o + i] * x[i]
		h[j] = s
		o += n_in
	for j in n_hidden:
		h[j] = tanh(h[j] + w[o + j])
	o += n_hidden
	var out := PackedFloat32Array()
	out.resize(n_out)
	for k in n_out:
		var s := 0.0
		for j in n_hidden:
			s += w[o + j] * h[j]
		out[k] = s
		o += n_hidden
	for k in n_out:
		out[k] += w[o + k]
	return out
