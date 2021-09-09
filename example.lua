require('teeswift')

local a = Node('a')
a[#a+1] = Node('b')
a[#a+1] = Node('c')

print(a:newick())