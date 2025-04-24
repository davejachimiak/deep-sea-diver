# Deep Sea Diver

This generates Mermaid charts from user prompts. Wrapper prompts are geared towards

This currently only supports Anthropic Claude 3.7. Get your API key [here](https://www.anthropic.com/api).

## Installation

Download. Clone this repo.

```sh
git clone git@github.com:davejachimiak/deep-sea-diver.git
cd deep-sea-diver
```

Install Ruby dependencies.

```sh
bundle install
```

Install the [mermaid CLI](https://github.com/mermaid-js/mermaid-cli).

```sh
https://github.com/mermaid-js/mermaid-cli
```

## Usage

```sh
ANTHROPIC_API_KEY=<key> ruby main.rb
```

## What to expect

The wrapper prompts nudge responses to return code for multiple Mermaid charts on every request.

The script will persist that code to the ./db directory, persist diagram PNGs with the Mermaid CLI, and open those diagrams.