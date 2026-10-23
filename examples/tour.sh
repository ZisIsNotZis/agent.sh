echo 'a block is text, and this shell runs it; the reply is what it printed'
%%
pwd; ls
%%
bgrun -n 'a job reports when it is done, not when it starts' sleep 3
%%
echo 'the model keeps writing blocks while the job runs'
%%
bgwait
%%
for i in $(seq 1 150); do echo "line $i"; done
