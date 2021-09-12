require('../teeswift')

-- http://lua-users.org/wiki/FileInputOutput
-- local lines = {}
for line in io.lines(arg[1]) do
    print(read_tree_newick(line):newick())
end