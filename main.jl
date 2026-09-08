using HTTP
#using PromptingTools: SystemMessage, UserMessage, OllamaManagedSchema, render, aigenerate
using JSON3

const OLLAMA_URL = "http://localhost:11434/api/generate"
#const OLLAMA_MODEL = "gemma4:12b-mlx"
const OLLAMA_MODEL = "lfm2.5:latest"
const THINKING_TAG_PATTERN = r"<(?:think|redacted_thinking)>[\s\S]*?</think>"

strip_thinking(content::AbstractString) = strip(replace(content, THINKING_TAG_PATTERN => ""))

greet() = print("Hello World!")

const SENTIMENT_PROMPT = [
    SystemMessage("""
        You are an expert, objective data annotation assistant. Your task is to perform one-shot sentiment analysis. Analyze the provided customer text and classify its overall sentiment into exactly one of three categories: Positive, Negative, or Neutral. Respond ONLY with the category name. Do not include any introductory words, explanations, or punctuation.
        Do not include any other text or formatting in your response. No thinking output. Just the category name.
        Example:
        Text: "The battery life is terrible, but the camera is great."
        Sentiment: Neutral
        """),
    UserMessage("""Text: {{text}}
        Sentiment:""")
]

function ollama_prompt(text::String)
    rendered = render(OllamaManagedSchema(), SENTIMENT_PROMPT; text)
    response = HTTP.post(
        OLLAMA_URL,
        body = JSON3.write(Dict(
            "model" => OLLAMA_MODEL,
            "system" => rendered.system,
            "prompt" => rendered.prompt,
            "think" => false,
            "options" => Dict("temperature" => 0.0),
        )),
    )
    parsed = JSON3.read(String(response.body))
    return strip_thinking(get(parsed, :response, ""))
end

function ollama_sentiment(text::String)
    msg = aigenerate(
        OllamaManagedSchema(),
        SENTIMENT_PROMPT;
        text,
        model = OLLAMA_MODEL,
        api_kwargs = (think = false, options = Dict("temperature" => 0.0)),
    )
    return strip_thinking(msg.content)
end


