defmodule Membrane.AudioFiller do
  @moduledoc """
  Element ensures that audio will be consistent by filling 'holes' with silence.
  In order for AudioFiller to work properly, all buffers processed have to have correct timestamps (pts).
  """

  use Membrane.Filter
  alias Membrane.Buffer
  alias Membrane.RawAudio

  def_options min_audio_loss: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.millisecond(),
                description: """
                Minimal time of audio loss in nanoseconds that filler should fill with silence
                """
              ]

  def_input_pad :input,
    accepted_format: RawAudio,
    demand_mode: :auto

  def_output_pad :output,
    accepted_format: RawAudio,
    demand_mode: :auto

  @impl true
  def handle_init(_context, %__MODULE__{} = options) do
    state =
      options
      |> Map.from_struct()
      |> Map.merge(%{
        last_pts: nil,
        last_payload_duration: nil
      })

    {[], state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, %{last_pts: nil} = state) do
    last_payload_duration =
      RawAudio.bytes_to_time(byte_size(buffer.payload), ctx.pads.input.stream_format)

    {[buffer: {:output, buffer}],
     %{state | last_pts: buffer.pts, last_payload_duration: last_payload_duration}}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) do
    pts_duration = buffer.pts - state.last_pts
    lost_audio_duration = pts_duration - state.last_payload_duration

    buffers =
      if lost_audio_duration > state.min_audio_loss do
        new_pts = state.last_pts + state.last_payload_duration

        [
          %Buffer{
            pts: new_pts,
            payload: RawAudio.silence(ctx.pads.input.stream_format, lost_audio_duration)
          },
          buffer
        ]
      else
        [buffer]
      end

    current_payload_duration =
      RawAudio.bytes_to_time(byte_size(buffer.payload), ctx.pads.input.stream_format)

    {[buffer: {:output, buffers}],
     %{state | last_pts: buffer.pts, last_payload_duration: current_payload_duration}}
  end
end
