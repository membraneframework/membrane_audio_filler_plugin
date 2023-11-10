defmodule Membrane.AudioFillerTest do
  @moduledoc """
  Tests for AudioFiller module.
  """
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias Membrane.Buffer
  alias Membrane.RawAudio
  alias Membrane.Testing.Pipeline

  @stream_format %RawAudio{
    channels: 1,
    sample_rate: 48_000,
    sample_format: :s16le
  }

  test "AudioFiller returns the same buffers as its gets" do
    buffer_duration = Membrane.Time.milliseconds(10)

    buffer_generator = fn x ->
      %Buffer{
        pts: buffer_duration * x,
        payload: RawAudio.silence(@stream_format, buffer_duration)
      }
    end

    pipeline = build_pipeline(buffer_generator)

    assert_end_of_stream(pipeline, :sink)

    Enum.each(0..9, fn x ->
      pts = buffer_duration * x
      payload = RawAudio.silence(@stream_format, buffer_duration)

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{
        pts: ^pts,
        payload: ^payload
      })
    end)

    Pipeline.terminate(pipeline)
  end

  test "AudioFiller returns the same buffers as its gets plus additional buffers to fill holes in audio stream" do
    buffer_duration = Membrane.Time.milliseconds(10)

    wrong_buffer_generator = fn x ->
      %Buffer{
        pts: buffer_duration * 2 * x,
        payload: RawAudio.silence(@stream_format, buffer_duration)
      }
    end

    pipeline = build_pipeline(wrong_buffer_generator)

    assert_end_of_stream(pipeline, :sink)

    Enum.each(0..18, fn x ->
      pts = buffer_duration * x
      payload = RawAudio.silence(@stream_format, buffer_duration)

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{
        pts: ^pts,
        payload: ^payload
      })
    end)

    Pipeline.terminate(pipeline)
  end

  test "AudioFiller doesn't create additional buffers when hole in audio stream is smaller then min_audio_loss" do
    buffer_duration = Membrane.Time.millisecond() / 2

    wrong_buffer_generator = fn x ->
      %Buffer{
        pts: buffer_duration * 2 * x,
        payload: RawAudio.silence(@stream_format, buffer_duration)
      }
    end

    pipeline = build_pipeline(wrong_buffer_generator)

    assert_end_of_stream(pipeline, :sink)

    Enum.each(0..9, fn x ->
      pts = buffer_duration * 2 * x
      payload = RawAudio.silence(@stream_format, buffer_duration)

      assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{
        pts: ^pts,
        payload: ^payload
      })
    end)

    refute_sink_buffer(pipeline, :sink, Membrane.Buffer)

    Pipeline.terminate(pipeline)
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

    new_pts =
      last_buffer.pts +
        RawAudio.bytes_to_time(byte_size(last_buffer.payload), state.stream_format)

    {actions, %{state | buffers_no: new_buffers_no, pts: new_pts}}
  end

  defp build_pipeline(buffer_generator) do
    spec = [
      child(:source, %Membrane.Testing.Source{
        stream_format: @stream_format,
        output:
          {%{
             buffer_generator: buffer_generator,
             stream_format: @stream_format,
             buffers_no: 10,
             pts: 0
           }, &source_generator/2}
      }),
      get_child(:source)
      |> child(:filler, Membrane.AudioFiller)
      |> child(:sink, Membrane.Testing.Sink)
    ]

    Pipeline.start_link_supervised!(spec: spec)
  end
end
