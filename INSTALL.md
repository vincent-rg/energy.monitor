# Installation et gestion du widget

## Supprimer le widget (installation locale)

```bash
rm -rf ~/.local/share/plasma/plasmoids/energy.monitor
```

## Packager le widget

Crée un fichier `.plasmoid` (archive zip) :

```bash
cd /chemin/vers/energy.monitor/git
zip -r ../energy.monitor.plasmoid metadata.json metadata.desktop contents/
```

## Installer le widget

### Depuis le répertoire source (développement)

```bash
kpackagetool6 --install /chemin/vers/energy.monitor/git --type Plasma/Applet
```

### Depuis un fichier `.plasmoid`

```bash
kpackagetool6 --install energy.monitor.plasmoid --type Plasma/Applet
```

### Mettre à jour une installation existante

Supprimer d'abord l'ancienne installation, puis réinstaller :

```bash
rm -rf ~/.local/share/plasma/plasmoids/energy.monitor
kpackagetool6 --install /chemin/vers/energy.monitor/git --type Plasma/Applet
```

## Relancer le bureau (plasmashell)

```bash
plasmashell --replace &
```

> Le bureau va clignoter brièvement le temps du redémarrage.
> Nécessaire après chaque installation/mise à jour du widget.

## Ajouter le widget au bureau

Après installation et redémarrage du bureau :
clic droit sur le bureau → **Ajouter des widgets** → rechercher **Energy monitor**.
