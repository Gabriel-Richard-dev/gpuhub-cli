#!/usr/bin/env bash
# Instalador do cliente do GPU Hub (máquina de dev, do lab ou de casa).
#
#   curl -fsSL https://raw.githubusercontent.com/Gabriel-Richard-dev/gpuhub-cli/main/install.sh | bash
#
# Faz, sem sudo:
#   1. pergunta o endereço do hub (Enter = 10.50.21.252)
#   2. instala o cliente `gpuhub` em ~/.local/bin e põe no PATH (bash e fish)
#   3. baixa a CA interna do hub e mostra o fingerprint pra você conferir com
#      o que o admin passou (é isso que impede alguém no meio de se passar
#      pelo hub: o resto do TLS confia nessa CA)
#   4. roda `gpuhub login`: você cola a sua API key, ou aperta Enter pra
#      pedir acesso (nome, email institucional, motivo) e espera a aprovação
#
# Por que vem do GitHub e não do próprio hub: o GitHub tem certificado
# público, então o instalador chega íntegro sem precisar de `curl -k`. Só a
# CA do hub é baixada sem verificação — e é exatamente ela que você confere
# pelo fingerprint.
#
# Variáveis (pra pular as perguntas ou testar):
#   GPUHUB_URL         endereço do hub; definida, não pergunta
#   GPUHUB_CLIENT_URL  de onde baixar o cliente (padrão: bin/gpuhub do GitHub)
#
# Rodar de novo é seguro: atualiza o cliente e, se a key já funciona, não
# pede login de novo.
set -euo pipefail

DEFAULT_URL="https://10.50.21.252"
CLIENT_URL="${GPUHUB_CLIENT_URL:-https://raw.githubusercontent.com/Gabriel-Richard-dev/gpuhub-cli/main/bin/gpuhub}"
BIN_DIR="$HOME/.local/bin"

# Tudo dentro de main(), chamada só na última linha: no `curl | bash` o bash
# lê o script do pipe aos poucos; assim ele lê o arquivo inteiro antes de
# executar qualquer coisa (download pela metade não roda meio instalador).
# Pelo mesmo motivo, todo comando que poderia ler stdin recebe /dev/tty ou
# /dev/null — senão ele "comeria" o resto do script do pipe.

# Tem terminal pra perguntar? No curl|bash o stdin é o pipe, mas o /dev/tty
# continua sendo o teclado. Sem terminal (CI, ssh sem -t), segue os padrões.
has_tty() { { : </dev/tty; } 2>/dev/null; }

# ask "pergunta" "padrão" -> imprime a resposta (ou o padrão no Enter/sem tty)
ask() {
  local ans=""
  if has_tty; then
    printf '%s' "$1" >/dev/tty
    IFS= read -r ans </dev/tty || ans=""
  fi
  printf '%s' "${ans:-$2}"
}

main() {
  echo "== GPU Hub: instalação do cliente =="

  # 1) dependências de sistema; se faltar algo, diz como instalar e para
  local missing=() c
  for c in curl python3 tar openssl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "erro: faltam: ${missing[*]}" >&2
    echo "      Ubuntu/Debian: sudo apt install ${missing[*]}" >&2
    exit 1
  fi

  # 2) endereço do hub: IP, nome ou URL; sem esquema vira https://
  local url="${GPUHUB_URL:-}"
  if [ -z "$url" ]; then
    url="$(ask "IP ou endereço do GPU Hub [${DEFAULT_URL#https://}]: " "$DEFAULT_URL")"
  fi
  url="${url//[[:space:]]/}"
  case "$url" in
    http://*|https://*) ;;
    *) url="https://$url" ;;
  esac
  url="${url%/}"
  echo "-> hub: $url"

  # 3) cliente em ~/.local/bin (baixa num .tmp e move: um download que falha
  #    no meio não deixa um gpuhub quebrado no lugar do que funcionava)
  echo "-> baixando o cliente gpuhub para $BIN_DIR"
  mkdir -p "$BIN_DIR"
  curl -fsSL "$CLIENT_URL" -o "$BIN_DIR/gpuhub.tmp" </dev/null \
    || { rm -f "$BIN_DIR/gpuhub.tmp"; echo "erro: não consegui baixar o cliente de $CLIENT_URL" >&2; exit 1; }
  head -n1 "$BIN_DIR/gpuhub.tmp" | grep -q '^#!' \
    || { rm -f "$BIN_DIR/gpuhub.tmp"; echo "erro: o que veio de $CLIENT_URL não parece o cliente" >&2; exit 1; }
  mv "$BIN_DIR/gpuhub.tmp" "$BIN_DIR/gpuhub"
  chmod +x "$BIN_DIR/gpuhub"

  # 4) PATH no bash e no fish (o lab usa os dois); idempotente
  local pathline='export PATH="$HOME/.local/bin:$PATH"'
  if ! grep -qF "$pathline" "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# gpuhub\n%s\n' "$pathline" >> "$HOME/.bashrc"
  fi
  if [ -d "$HOME/.config/fish" ] || command -v fish >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/fish/conf.d"
    printf '# gpuhub\nfish_add_path "$HOME/.local/bin"\n' > "$HOME/.config/fish/conf.d/gpuhub.fish"
  fi
  export PATH="$BIN_DIR:$PATH"
  if [ -d "$HOME/.gpuhub-venv" ]; then
    echo "(o ~/.gpuhub-venv do cliente antigo com Ray não é mais usado; pode apagar: rm -rf ~/.gpuhub-venv)"
  fi

  # 5) o hub responde? A CA é servida sem auth de propósito (você precisa dela
  #    antes de confiar no hub). -k só aqui: quem valida é você, pelo fingerprint.
  # global (não local): o trap de EXIT roda depois que main() já retornou
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  #    Hub com certificado público não tem /ca.crt: aí basta ele responder algo.
  local code=000
  curl -fsSk --connect-timeout 5 --max-time 15 "$url/ca.crt" -o "$TMPD/ca.crt" </dev/null 2>/dev/null \
    || code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 "$url/api/health" </dev/null 2>/dev/null || true)"
  [ -s "$TMPD/ca.crt" ] && code=200
  if [ "${code:-000}" = 000 ]; then
    echo
    echo "Aviso: não alcancei $url — está na rede do campus/VPN?"
    echo "O cliente já está instalado; quando tiver acesso ao hub, rode:"
    echo
    echo "    gpuhub login $url"
    echo
    echo "Se 'gpuhub' não for encontrado, abra um terminal novo (o PATH mudou)."
    exit 0
  fi

  if [ -s "$TMPD/ca.crt" ] && openssl x509 -in "$TMPD/ca.crt" -noout >/dev/null 2>&1; then
    local fp; fp="$(openssl x509 -in "$TMPD/ca.crt" -noout -fingerprint -sha256 | cut -d= -f2)"
    echo
    echo "CA do hub (SHA-256):"
    echo "    $fp"
    local ok; ok="$(ask "Confere com o que o admin passou? [S/n] " "S")"
    case "$ok" in
      [nN]*)
        echo "Abortado: o fingerprint não confere. NÃO cole sua key; avise o admin do hub." >&2
        echo "(o cliente ficou instalado, mas sem credencial nenhuma)" >&2
        exit 1 ;;
    esac
  else
    # Com Let's Encrypt o /ca.crt não existe: o certificado já é público.
    echo "-> o hub usa certificado público (sem CA própria)"
  fi

  # 6) login. Reinstalação com key que já funciona: não pergunta de novo.
  echo
  if [ -s "$HOME/.gpuhub/key" ] && GPUHUB_URL="$url" gpuhub whoami </dev/null >/dev/null 2>&1; then
    echo "-> esta máquina já tem uma key válida; login mantido"
  elif has_tty; then
    echo "-> login no hub: cole a sua API key, ou Enter pra pedir acesso"
    gpuhub login "$url" </dev/tty || {
      echo >&2
      echo "O login não terminou. O cliente está instalado; quando quiser, rode:" >&2
      echo "    gpuhub login $url" >&2
      exit 1
    }
  else
    echo "Sem terminal pra perguntar a key. O cliente está instalado; depois rode:"
    echo "    gpuhub login $url                  (cola a key ou pede acesso)"
    echo "    gpuhub login --key ghk_... $url    (sem perguntar)"
    exit 0
  fi

  # 7) teste rápido: quem sou eu e como está a fila
  echo
  echo "-> testando"
  gpuhub whoami </dev/null || echo "Aviso: 'gpuhub whoami' falhou (veja a mensagem acima)." >&2
  gpuhub queue </dev/null || echo "Aviso: 'gpuhub queue' falhou (veja a mensagem acima)." >&2

  cat <<FIM

Pronto! Como usar:
  - Terminal:   gpuhub submit train/seu_treino.py   (manda e acompanha o log)
                gpuhub queue | gpuhub logs <id> | gpuhub stop <id>
  - Resultados: gpuhub pull <id>   (o que o job gravou em /data/home/jobs/<id>)
  - Dados:      gpuhub push pasta/  (o job lê em /data/home; compartilhados em /data/datasets)
  - VSCode:     no vigia-ia-lab, escolha a config do GPU Hub e aperte F5
  - Navegador:  $url/jobs

Se 'gpuhub' não for encontrado, abra um terminal novo (o PATH mudou).
FIM
}

main "$@"
