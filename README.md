# gpuhub-cli

Cliente de linha de comando do **GPU Hub**, a GPU compartilhada do laboratório.
Você manda um script Python do seu computador, ele roda na GPU do hub e o log
aparece ao vivo no seu terminal. O que o treino salvar (pesos, gráficos) fica na
sua pasta no hub, e você baixa com um comando.

É só um script bash. Precisa de `bash`, `curl`, `python3`, `tar` e `openssl`.
Não precisa de GPU, venv nem sudo.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/Gabriel-Richard-dev/gpuhub-cli/main/install.sh | bash
```

O instalador:

1. pergunta o endereço do hub (Enter usa o padrão, `10.50.21.252`);
2. instala o `gpuhub` em `~/.local/bin` e põe essa pasta no PATH (bash e fish);
3. baixa a CA interna do hub e mostra o **fingerprint SHA-256**. Confira com o
   que o admin passou: é isso que garante que você está falando com o hub de
   verdade;
4. roda `gpuhub login`, que pede a sua API key. Se você ainda não tem uma,
   aperte Enter para pedir acesso.

Pode rodar de novo quando quiser: o cliente é atualizado e, se a sua key ainda
funciona, ele não pergunta de novo.

## Pedir acesso

Você não precisa de conta: o acesso é por uma **API key pessoal**.

```bash
gpuhub login          # Enter na pergunta da key
# ou direto:
gpuhub request-access
```

Ele pede seu nome, **email institucional** e o motivo (projeto, orientador) e
fica esperando. Quando um professor ou admin aprovar, a key é entregue **só para
você, uma vez**, e fica salva em `~/.gpuhub/key` (permissão 600). Ninguém mais
vê a sua key, nem o admin.

Se fechar o terminal antes da aprovação, rode `gpuhub login` depois: ele retoma
a espera em vez de pedir de novo.

Recebeu uma key do professor? Use `gpuhub login` e cole a key, ou
`gpuhub login --key ghk_...`.

## Usar

```bash
gpuhub submit train/treino.py --epochs 10   # envia a pasta e acompanha o log
gpuhub queue                                # o que roda e o que espera
gpuhub logs 42                              # volta a acompanhar o job 42
gpuhub stop 42                              # cancela
gpuhub pull 42                              # baixa os resultados para ./job-42/
```

- O `submit` envia a raiz do repositório git do script (ou a pasta dele) sem
  `.git`, venvs e caches. Liste no `.gpuhubignore` o que mais não deve subir.
- Um `requirements.txt` na raiz é instalado no hub antes de rodar. Pacotes
  extras: `gpuhub submit --pip "onnx,timm" treino.py`.
- Ctrl+C só larga o log; o job continua no hub.

**VSCode com o vigia-ia-lab:** abra o repositório, escolha a configuração do
GPU Hub no "Run and Debug" e aperte **F5**. Ele usa a mesma key do `gpuhub`.

### Arquivos dentro do job

| Caminho no job   | O que é                                                  |
|------------------|----------------------------------------------------------|
| `/workspace`     | o seu código (cwd do script)                             |
| `/data/home`     | a sua pasta no hub (leitura e escrita)                   |
| `/data/datasets` | datasets compartilhados do lab (só leitura)              |

O job também recebe as variáveis `GPUHUB_HOME`, `GPUHUB_DATASETS`,
`GPUHUB_JOB_ID` e `GPUHUB_USER`. Cada job ganha a pasta `home/jobs/<id>/`, com o
código e o `log.txt`. Salve os resultados ali ou em qualquer lugar de
`/data/home`.

Dados grandes não devem ir no `submit` (sobem a cada envio). Mande uma vez e
leia de `/data/home`:

```bash
gpuhub push meu_dataset/              # vai para home/meu_dataset/
gpuhub files home/meu_dataset         # lista
gpuhub pull home/runs/melhor.pt .     # baixa um arquivo ou pasta
gpuhub rm -r home/runs/velho          # apaga (só dentro de home)
```

## Comandos

| Comando | O que faz |
|---|---|
| `gpuhub login [url]` | cola a API key, ou Enter para pedir acesso |
| `gpuhub login --key ghk_... [url]` | o mesmo, sem perguntar |
| `gpuhub request-access` | pede acesso e espera a aprovação |
| `gpuhub whoami` | usuário, papéis e validade da key |
| `gpuhub submit [-C pasta] [--pip pkgs] [--no-follow] script.py [args]` | roda um script na GPU |
| `gpuhub queue [--all]` | fila e últimos jobs |
| `gpuhub logs <id> [--no-follow]` | log do job |
| `gpuhub stop <id>` | cancela o job |
| `gpuhub status <id>` | detalhes do job (JSON) |
| `gpuhub files [caminho]` | lista `home/...` ou `datasets/...` |
| `gpuhub push <arquivo\|pasta> [destino]` | envia (padrão: `home`) |
| `gpuhub pull <id\|caminho> [destino]` | baixa resultados de um job ou um caminho |
| `gpuhub mkdir <caminho>` / `gpuhub rm [-r] <caminho>` | cria / apaga |
| `gpuhub logout` | apaga a credencial desta máquina |

## Problemas comuns

- **"não alcancei https://...; você está na rede do campus/VPN?"**: o hub só é
  acessível de dentro da rede do campus. De casa, conecte na VPN primeiro.
- **Erro de certificado**: rode `gpuhub login` de novo para baixar a CA do hub
  outra vez. Se o fingerprint mostrado pelo instalador não bater com o do
  admin, não cole a key e avise o admin.
- **"key revogada" ou "key expirada"**: peça uma nova com
  `gpuhub request-access` ou fale com o professor.
- **`gpuhub: command not found`**: abra um terminal novo (o PATH mudou na
  instalação).
- **413 / envio grande demais**: tire dados e checkpoints da pasta (use o
  `.gpuhubignore`) e mande os dados com `gpuhub push`.

## Admin e professor

Admins e professores entram com a conta do Keycloak do lab:

```bash
gpuhub login --admin              # abre uma URL para aprovar no navegador
gpuhub admin requests             # pedidos pendentes
gpuhub admin approve 7 --role pesquisador --days 180
gpuhub admin deny 8
gpuhub admin users                # quem tem key, validade, último uso
gpuhub admin revoke fulano        # efeito imediato
gpuhub admin rotate fulano        # revoga e gera uma nova (mostrada a você)
gpuhub admin add "Nome" email@ifce.edu.br --role professor
```

Ao aprovar um pedido, a key vai direto para quem pediu; o admin não a vê. Só em
`add` e `rotate` a key aparece para o admin, uma única vez, para ele repassar
por um canal privado.

Tudo isso também está na página web do hub, em `https://<hub>/jobs`: fila, logs
ao vivo, GPU, arquivos e a aba de pedidos de acesso.

## Licença

MIT
