--[[

  Training script 

--]]

require('..')

-- Pearson correlation
function pearson(x, y)
  x = x - x:mean()
  y = y - y:mean()
  return x:dot(y) / (x:norm() * y:norm())
end

-- read command line arguments
local args = lapp [[
Training script for semantic relatedness prediction on the SICK dataset.
  -m,--model  (default dependency) Model architecture: [dependency, lstm, bilstm]
  -l,--layers (default 1)          Number of layers (ignored for Tree-LSTM)
  -d,--dim    (default 150)        LSTM memory dimension
]]

local model_name, model_class, model_structure
if args.model == 'dependency' then
  model_name = 'Dependency Tree LSTM'
  model_class = treelstm.TreeLSTMSim
  model_structure = args.model
elseif args.model == 'lstm' then
  model_name = 'LSTM'
  model_class = treelstm.LSTMSim
  model_structure = args.model
elseif args.model == 'bilstm' then
  model_name = 'Bidirectional LSTM'
  model_class = treelstm.LSTMSim
  model_structure = args.model
end
header(model_name .. ' for Semantic Relatedness')

-- directory containing dataset files
local data_dir = 'training/'

-- load vocab
local vocab = treelstm.Vocab(data_dir .. 'trainvocab-cased.txt')

-- load embeddings
print('loading word embeddings')
local emb_dir = 'glove/'
local emb_prefix = emb_dir .. 'glove.840B'
local emb_vocab, emb_vecs = treelstm.read_embedding(emb_prefix .. '.vocab', emb_prefix .. '.300d.th')
local emb_dim = emb_vecs:size(2)

-- use only vectors in vocabulary (not necessary, but gives faster training)
local num_unk = 0
local vecs = torch.Tensor(vocab.size, emb_dim)
for i = 1, vocab.size do
  local w = vocab:token(i)
  if emb_vocab:contains(w) then
    vecs[i] = emb_vecs[emb_vocab:index(w)]
  else
    num_unk = num_unk + 1
    vecs[i]:uniform(-0.05, 0.05)
  end
end
print('unk count = ' .. num_unk)
emb_vocab = nil
emb_vecs = nil
collectgarbage()

-- load datasets
print('loading datasets')
local train_dir = data_dir .. 'train/'
local dev_dir = data_dir .. 'dev/'
local train_dataset = treelstm.read_relatedness_dataset(train_dir, vocab)
local dev_dataset = treelstm.read_relatedness_dataset(dev_dir, vocab)
printf('num train = %d\n', train_dataset.size)
printf('num dev   = %d\n', dev_dataset.size)

-- initialize model
local model = model_class{
  --emb_vecs   = vecs,
  structure  = model_structure,
  num_layers = args.layers,
  mem_dim    = args.dim,
}
local emb_vecs=vecs
-- number of epochs to train
local num_epochs = 10

-- print information
header('model configuration')
printf('max epochs = %d\n', num_epochs)
model:print_config()

-- train
local train_start = sys.clock()
local best_dev_score = -1.0
local best_dev_model = model
header('Training model')
for i = 1, num_epochs do
  local start = sys.clock()
  printf('-- epoch %d\n', i)
  model:train(train_dataset, emb_vecs)
  printf('-- finished epoch in %.2fs\n', sys.clock() - start)

  -- uncomment to compute train scores
  --[[
  local train_predictions = model:predict_dataset(train_dataset)
  local train_score = pearson(train_predictions, train_dataset.labels)
  printf('-- train score: %.4f\n', train_score)
  --]]

  local dev_predictions = model:predict_dataset(dev_dataset,emb_vecs)
  local dev_score = pearson(dev_predictions, dev_dataset.labels)
  printf('-- dev score: %.4f\n', dev_score)

  if dev_score > best_dev_score then
    best_dev_score = dev_score
    best_dev_model = model_class{
      structure = model_structure,
      num_layers = args.layers,
    }
    best_dev_model.params:copy(model.params)
  end
end
printf('finished training in %.2fs\n', sys.clock() - train_start)

-- write model to disk
if lfs.attributes(treelstm.models_dir) == nil then
  lfs.mkdir(treelstm.models_dir)
end
printf('Saving model with dev score = %.4f\n', best_dev_score)
local model_save_path = string.format(
  treelstm.models_dir .. '/rel-%s.%dl.%dd.th', args.model, args.layers, args.dim)
print('writing model to ' .. model_save_path)
best_dev_model:save(model_save_path)

-- to load a saved model
-- local loaded = model_class.load(model_save_path)
