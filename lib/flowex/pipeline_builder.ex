defmodule Flowex.PipelineBuilder do
  import Supervisor.Spec

  def start(pipeline_module, opts) do
    {:ok, sup_pid} = Flowex.Supervisor.start_link(pipeline_module)
    [{{Flowex.Producer, _, _}, in_producer, :worker, [Flowex.Producer]}] = Supervisor.which_children(sup_pid)

    last_pids = pipeline_module.pipes()
    |> Enum.reduce([in_producer], fn({atom, count}, prev_pids) ->
      pids = (1..count)
      |> Enum.map(fn(i) ->
        {:ok, pid} = case Atom.to_char_list(atom) do
          ~c"Elixir." ++ _ -> init_module_pipe(sup_pid, {atom, opts}, prev_pids)
          _ ->  init_function_pipe(sup_pid, {pipeline_module, atom, opts}, prev_pids)
        end
        pid
      end)
      pids
    end)

    worker_spec = worker(Flowex.Consumer, [last_pids], [id: {Flowex.Consumer, nil, make_ref()}])
    {:ok, out_consumer} = Supervisor.start_child(sup_pid, worker_spec)

    Experimental.GenStage.demand(in_producer, :forward)
    %Flowex.Pipeline{module: pipeline_module, in_pid: in_producer, out_pid: out_consumer, sup_pid: sup_pid}
  end

  def stop(sup_pid) do
    Supervisor.which_children(sup_pid)
    |> Enum.each(fn({id, pid, :worker, [_]}) ->
      Supervisor.terminate_child(sup_pid, id)
    end)
    Supervisor.stop(sup_pid)
  end

  defp init_function_pipe(sup_pid, {pipeline_module, function, opts}, prev_pids) do
    worker_spec = worker(Flowex.Stage, [{pipeline_module, function, opts, prev_pids}], [id: {__MODULE__, function, make_ref()}])
    Supervisor.start_child(sup_pid, worker_spec)
  end

  defp init_module_pipe(sup_pid, {module, opts}, prev_pids) do
    opts = module.init(opts)
    worker_spec = worker(Flowex.Stage, [{module, :call, opts, prev_pids}], [id: {module, :call, make_ref()}])
    Supervisor.start_child(sup_pid, worker_spec)
  end
end
