# copy over files
if [[ ! -f default.config ]]; then
    cp example.config default.config
    cp dev.sample dev.config
fi

# Clean-up
rm -f erl_crash.dump *.beam trace_*.txt

# Compile
erlc +debug_info *.erl
