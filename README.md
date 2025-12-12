# ☁️ Guía de Despliegue Salesforce con VS Code

Esta guía documenta el paso a paso para subir Lightning Web Components (LWC) y clases Apex a una organización de Salesforce utilizando Visual Studio Code.

## 📋 Prerrequisitos

Antes de empezar, asegúrate de tener instalado:
1.  **Visual Studio Code (VS Code)**.
2.  **Salesforce CLI** (Command Line Interface).
3.  **Salesforce Extension Pack** (Instalar desde el Marketplace de VS Code).

---

## 🚀 Parte 1: Configuración Inicial (La primera vez)

Si inicias un proyecto desde cero, sigue estos pasos:

### 1. Crear el Proyecto
1.  Abre VS Code.
2.  Abre la **Paleta de Comandos**: `Ctrl + Shift + P` (Win) / `Cmd + Shift + P` (Mac).
3.  Escribe y selecciona: `SFDX: Create Project with Manifest`.
4.  Selecciona la plantilla **Standard**.
5.  Asigna un nombre al proyecto y elige la carpeta donde guardarlo.

### 2. Autorizar la Org (Conectar)
1.  Abre la Paleta de Comandos (`Ctrl + Shift + P`).
2.  Escribe y selecciona: `SFDX: Authorize an Org`.
3.  Elige el tipo de entorno:
    * **Production:** Para entornos productivos o Developer Edition.
    * **Sandbox:** Para entornos de prueba (QA, UAT).
4.  Escribe un **Alias** (nombre corto) para identificar la org (ej: `DevSandbox`, `Prod`).
5.  Se abrirá el navegador. Inicia sesión y permite el acceso.

---

## 🔄 Parte 2: Flujo de Trabajo Diario (Subidas Sucesivas)

Una vez configurado el proyecto, usa estos métodos para desplegar cambios.

### Opción A: Subir un archivo específico (Rápido)
Ideal cuando modificas solo una clase Apex o el HTML de un LWC.
1.  Abre el archivo que has editado.
2.  Haz **Clic Derecho** en cualquier parte del editor de texto.
3.  Selecciona: `SFDX: Deploy This Source to Org`.

### Opción B: Subir un componente completo (Bundle)
Ideal para LWC donde has tocado HTML, JS y CSS.
1.  En el explorador de archivos (izquierda), busca la carpeta del componente (ej: `force-app/main/default/lwc/miComponente`).
2.  Haz **Clic Derecho** sobre la carpeta.
3.  Selecciona: `SFDX: Deploy Source to Org`.

---

## 🌐 Parte 3: Gestión de Múltiples Orgs

Es crítico saber a qué entorno estás subiendo el código antes de desplegar.

### 1. ¿Cómo saber qué Orgs tengo conectadas?
Para ver la lista de orgs autorizadas y sus alias:

* **Opción Visual:** Paleta de Comandos > `SFDX: List All Orgs`.
* **Opción Terminal:** Ejecuta el comando:
    ```bash
    sf org list
    ```

### 2. ¿Cómo cambiar la Org de destino?
VS Code sube el código a la "Default Org" seleccionada en ese momento.

**Método Rápido (Barra de Estado):**
1.  Mira la **barra inferior azul** de VS Code.
2.  A la izquierda, verás un nombre/alias (ej: `MiDevOrg` o `No Default Org`).
3.  Haz clic en ese nombre.
4.  Selecciona del menú superior la org a la que quieres apuntar ahora.

**Método Paleta de Comandos:**
1.  `Ctrl + Shift + P` > `SFDX: Set a Default Org`.
2.  Elige la org deseada.

> **⚠️ IMPORTANTE:** Antes de hacer "Deploy", mira siempre la esquina inferior izquierda para confirmar que estás en la org correcta (ej: que no estés subiendo a Producción lo que querías probar en Sandbox).

---

## 🛠️ Solución de Errores Comunes

| Error | Causa Probable | Solución |
| :--- | :--- | :--- |
| **Deployment Failed** | Error de sintaxis (JS/Apex) o XML incorrecto. | Revisa la pestaña **Output** (Salida) en la terminal para ver el error exacto. |
| **LWC no visible en App Builder** | Falta exponer el componente. | En `miLWC.js-meta.xml`, asegura que `<isExposed>true</isExposed>` y define los `<targets>`. |
| **No Default Org Set** | VS Code no sabe dónde subir. | Haz clic en el texto "No Default Org" en la barra inferior y selecciona una. |


## Collection of Demo Components for Salesforce B2B/D2C Commerce
This is a collection of components built for Salesforce B2B and D2C Commerce mainly for Demo purposes, but they can be used for free and extended accordngly to your customer needs.
Me or Salesofrce doesn't give any support on this components since they are not ofiicialy distributed through the appexchange.

This collection currently contains
* [B2B Commerce CS (Customer Service) Free Product](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/B2B%20CS%20Free%20Product) A component that can be added to the cart giving specific users the ability to manually set products free or manually add % discounts to the product (mainly for order on behalf use cases)
* [B2B Visual Configurator](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/B2B%20Visual%20Configurator%20LWR) A component that allows to create complex product configurations using upcharge products (NOTE: the component uses added fields to the cart, cartitem, and product2 objects that are not included in the project so you will nedd to add them manually to your org in order to make the components to work)
* [Cart Switcher](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/LWR%20Cart%20Switcher) A component that allows customers to create multicle carts, switch between them and share them with other users
* [PDP OCI Availability Table](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/PDP%20OCI%20Availability%20Table) A component that should be used on orgs with Salesforce Order Management with Omnichannel Inventory enabled. Allows you to show inventory items for a specifiic location group for a given product
* [Size Color Grid](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/Size%20Color%20Grid) A copmponent that extends the fisibility of a product in the PDP to show size/color variants in a grid (NOTE: the component uses added fields to the product2 objects that are not included in the project so you will nedd to add them manually to your org in order to make the components to work)
* [Forced Account Switch](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/forcedAccountSwitch) A mix of components that allows to force an Effective Account Id passing that as an URL param (e.g. from a OOBO scenario from a partner community)
* [Barcode Scanner](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/lwrBarcodeScanner) A component that opens the device camera and scans for multiple barcodes for broducts to be added to the cart. This component require Mobile Publisher licenses to work
* [LWR Generic Related Component](https://github.com/DaniSpain/Salesforce-Commerce-on-Core/tree/main/lwrGenericRelated) A component that can be used in LWR websites to show any kind of related object in a catalog-like format

## Additional Resources
If you are looking for all the base components or official examples and guidelines used in Salesforce B2B/D2C Commerce you can refer to this repositories provided by Salesforce:
* [Commerce Extensibility Framework](https://github.com/forcedotcom/commerce-extensibility) Use this repository to find examples on how to use the Extension framework to extend pricing, taxes, inventory, etc capabilities
* [Commerce on Lightning Components](https://github.com/forcedotcom/commerce-on-lightning-components) A library to the reference implementation for the standard B2B and D2C Commerce on LWR framweork  Lightning Web Components
* [Commerce on Lightning](https://github.com/forcedotcom/commerce-on-lightning/) Another repository with additional examples on components, classes and more for B2B, D2C and SOM (Salesforce Order Manager)
* [B2B Commerce Lightning (Aura) Quick Start](https://github.com/forcedotcom/b2b-commerce-on-lightning-quickstart/) A remopistory containing examples regarding B2b Commerce Lightning Aura implementation (NOTE: for new project is highly recommended to use LWR instead, in taht case you can ignore this repo)

# Additional Documentation
* [Salesforce B2B/D2C Commerce Help](https://help.salesforce.com/s/articleView?id=sf.comm_intro.htm&type=5)
* [Salesforce B2B/D2C Commerce Developer Documentation](https://developer.salesforce.com/docs/atlas.en-us.b2b_b2c_comm_dev.meta/b2b_b2c_comm_dev/b2b_b2c_comm_dev_guide.htm)
* [Salesforce B2B/D2C Extension Developer Guide](https://developer.salesforce.com/docs/commerce/salesforce-commerce/guide/extensions.html)
