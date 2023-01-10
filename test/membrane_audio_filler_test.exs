defmodule Membrane.AudioFillerTest do
  @moduledoc """
  Tests for AudioFiller module.
  """
  use ExUnit.Case

  import Membrane.Testing.Assertions

  alias Membrane.Buffer
  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @caps %RawAudio{
    channels: 1,
    sample_rate: 48_000,
    sample_format: :s16le
  }

  test "AudioFiller returns the same buffers as its gets" do
    buffer_duration = Membrane.Time.milliseconds(10)

    buffer_generator = fn x ->
      %Buffer{pts: buffer_duration * x, payload: RawAudio.silence(@caps, buffer_duration)}
    end

    {:ok, pipeline} = build_pipeline(buffer_generator)

    assert_end_of_stream(pipeline, :sink)

    Enum.each(0..9, fn x ->
      pts = buffer_duration * x
      payload = RawAudio.silence(@caps, buffer_duration)

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{
        pts: ^pts,
        payload: ^payload
      })
    end)

    Pipeline.terminate(pipeline, blocking?: true)
  end

  test "AudioFiller returns the same buffers as its gets plus additional buffers to fill holes in audio stream" do
    buffer_duration = Membrane.Time.milliseconds(10)

    wrong_buffer_generator = fn x ->
      %Buffer{pts: buffer_duration * 2 * x, payload: RawAudio.silence(@caps, buffer_duration)}
    end

    {:ok, pipeline} = build_pipeline(wrong_buffer_generator)

    assert_end_of_stream(pipeline, :sink)

    Enum.each(0..18, fn x ->
      pts = buffer_duration * x
      payload = RawAudio.silence(@caps, buffer_duration)

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{
        pts: ^pts,
        payload: ^payload
      })
    end)

    Pipeline.terminate(pipeline, blocking?: true)
  end

  defp source_generator(%{buffers_no: buffers_no, pts: pts} = state, size) do
    size = min(size, buffers_no)
    new_buffers_no = buffers_no - size

    buffers =
      Enum.map(0..(size - 1), state.buffer_generator)
      |> Enum.map(fn buffer -> %{buffer | pts: buffer.pts + pts} end)

    actions =
      if new_buffers_no == 0,
        do: [buffer: {:output, buffers}, end_of_stream: :output],
        else: [buffer: {:output, buffers}]

    last_buffer = List.last(buffers)
    new_pts = last_buffer.pts + RawAudio.bytes_to_time(byte_size(last_buffer.payload), state.caps)
    {actions, %{state | buffers_no: new_buffers_no, pts: new_pts}}
  end

  defp build_pipeline(buffer_generator) do
    children = [
      source: %Membrane.Testing.Source{
        caps: @caps,
        output:
          {%{buffer_generator: buffer_generator, caps: @caps, buffers_no: 10, pts: 0},
           &source_generator/2}
      },
      filler: Membrane.AudioFiller,
      sink: Membrane.Testing.Sink
    ]

    options = [
      links: Membrane.ParentSpec.link_linear(children)
    ]

    Pipeline.start_link(options)
  end
end
