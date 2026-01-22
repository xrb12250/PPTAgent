# Running PPTAgent Locally with Ollama on Mac

This guide explains how to run PPTAgent completely locally on your Mac using Ollama, without requiring any external APIs.

## Overview

PPTAgent can run entirely locally by using:
- **Ollama** for LLM inference (replaces OpenAI/Claude/etc.)
- **Ollama** for image generation (replaces DALL-E, requires v0.14.3+)
- **DuckDuckGo** for web search (replaces Tavily API)
- **PyMuPDF** for PDF parsing (replaces MINERU API)

## Quick Setup

Run the automated setup script:

```bash
./scripts/setup_ollama_mac.sh
```

This script will:
1. Install Ollama via Homebrew
2. Pull recommended models for your system
3. Install required Python dependencies
4. Configure PPTAgent for local operation

## Manual Setup

### 1. Install Ollama

```bash
# Using Homebrew
brew install ollama

# Or download from https://ollama.ai
```

### 2. Start Ollama

```bash
ollama serve
```

### 3. Pull Required Models

Choose models based on your Mac's RAM:

| RAM | LLM Model | Vision Model |
|-----|-----------|--------------|
| 16GB | `llama3.2:3b` | `llava:7b` |
| 32GB | `llama3.2` | `llava:13b` |
| 64GB+ | `llama3.3:70b` | `llava:34b` |

```bash
# Example for 32GB Mac
ollama pull llama3.2
ollama pull llava:13b
```

### 4. Install Python Dependencies

```bash
# For local search (replaces Tavily)
pip install duckduckgo-search

# For local PDF parsing (replaces MINERU API)
pip install pymupdf4llm
```

### 5. Configure PPTAgent

Copy the Ollama configuration:

```bash
cp deeppresenter/deeppresenter/config.ollama.yaml deeppresenter/deeppresenter/config.yaml
```

Or create your own `config.yaml`:

```yaml
# Enable offline mode
offline_mode: true
context_folding: true

research_agent:
  base_url: "http://localhost:11434/v1"
  model: "llama3.2"
  api_key: "ollama"
  soft_response_parsing: true

design_agent:
  base_url: "http://localhost:11434/v1"
  model: "llama3.2"
  api_key: "ollama"
  soft_response_parsing: true

long_context_model:
  base_url: "http://localhost:11434/v1"
  model: "llama3.2"
  api_key: "ollama"
  soft_response_parsing: true

vision_model:
  base_url: "http://localhost:11434/v1"
  model: "llava"
  api_key: "ollama"
  is_multimodal: true
  soft_response_parsing: true

# Optional: Image generation (Ollama v0.14.3+ required)
t2i_model:
  base_url: "http://localhost:11434/v1"
  model: "x/flux2-klein"
  api_key: "ollama"
```

### 6. Set Environment Variables

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# PPTAgent Ollama Configuration
export PPTAGENT_OFFLINE_MODE=true
export USE_LOCAL_PDF_PARSER=true
export PPTAGENT_MODEL=llama3.2
export PPTAGENT_API_BASE=http://localhost:11434/v1
export PPTAGENT_API_KEY=ollama
```

Then reload:
```bash
source ~/.zshrc
```

## Running PPTAgent

### Web UI

```bash
python webui.py
```

Access at: http://localhost:7861

### MCP Server

```bash
pptagent-mcp
```

## Configuration Options

### Offline Mode

When `offline_mode: true` is set:
- Web searches are disabled (returns empty results)
- Image searches are disabled
- Content must be provided directly

### Local Search (DuckDuckGo)

If `offline_mode: false` but no Tavily API key is set:
- PPTAgent automatically uses DuckDuckGo for searches
- No API key required
- Works without any external API services

### Local PDF Parsing

Set `USE_LOCAL_PDF_PARSER=true` or leave `MINERU_API` unset:
- Uses PyMuPDF4LLM for PDF parsing
- Extracts text and images locally
- No external service required

## Recommended Models

### For General Use
- **llama3.2** - Good balance of speed and quality
- **llama3.3:70b** - Best quality (requires 64GB+ RAM)

### For Vision Tasks
- **llava:7b** - Fast, lower memory usage
- **llava:13b** - Better quality
- **llava:34b** - Best quality (requires 64GB+ RAM)

### For Code Generation
- **codellama** - Specialized for code
- **deepseek-coder** - Alternative code model

### For Image Generation (Experimental, v0.14.3+)

Ollama now supports local image generation on macOS. Available models:

| Model | Description | Use Case |
|-------|-------------|----------|
| `x/z-image-turbo` | 6B params, Alibaba Tongyi Lab | Photorealistic images |
| `x/flux2-klein` | Black Forest Labs | Fast generation |

```bash
# Pull an image generation model
ollama pull x/flux2-klein

# Or for photorealistic images
ollama pull x/z-image-turbo
```

To enable image generation in your config:

```yaml
t2i_model:
  base_url: "http://localhost:11434/v1"
  model: "x/flux2-klein"
  api_key: "ollama"
```

**Note:** Image generation is currently macOS only. Windows and Linux support coming soon.

## Troubleshooting

### Ollama Not Responding

```bash
# Check if Ollama is running
pgrep -x ollama

# Start Ollama
ollama serve

# Check available models
ollama list
```

### Model Not Found

```bash
# Pull the model first
ollama pull llama3.2

# Verify it's available
ollama list
```

### Out of Memory

- Use smaller models (e.g., `llama3.2:3b` instead of `llama3.2`)
- Close other applications
- Reduce context window in config

### Slow Performance

- Use quantized models (e.g., `llama3.2:3b-q4_0`)
- Enable Metal GPU acceleration (default on Mac)
- Reduce `max_context_folds` in config

## Performance Tips

1. **Use Metal GPU**: Ollama automatically uses Metal on Mac for GPU acceleration

2. **Adjust Context Size**: Reduce `context_window` in config for faster responses

3. **Model Quantization**: Use quantized versions for faster inference:
   ```bash
   ollama pull llama3.2:3b-q4_0
   ```

4. **Batch Processing**: Enable `context_folding` to manage memory better

## Comparison: Local vs Cloud

| Feature | Local (Ollama) | Cloud APIs |
|---------|----------------|------------|
| Cost | Free | Pay per token |
| Privacy | 100% local | Data sent to servers |
| Speed | Depends on hardware | Generally fast |
| Quality | Good (improving) | Best available |
| Internet | Not required | Required |
| Setup | More complex | Simple API keys |

## Advanced Configuration

### Custom Model Files

Create custom Ollama models with specific parameters:

```bash
# Create a Modelfile
cat > Modelfile << 'EOF'
FROM llama3.2
PARAMETER temperature 0.7
PARAMETER num_ctx 4096
SYSTEM You are a helpful assistant for creating presentations.
EOF

# Create the model
ollama create pptagent-custom -f Modelfile
```

### Multiple Endpoints

You can configure multiple Ollama instances for load balancing:

```yaml
research_agent:
  base_url: "http://localhost:11434/v1"
  model: "llama3.2"
  api_key: "ollama"
  endpoints:
    - base_url: "http://localhost:11435/v1"
      model: "llama3.2"
      api_key: "ollama"
```

## Support

For issues specific to Ollama setup:
- Ollama Documentation: https://ollama.ai/docs
- PPTAgent Issues: https://github.com/anthropics/PPTAgent/issues
