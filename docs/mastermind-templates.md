# Mastermind templates configuration

If you want to configure custom mastermind templates, you should:

1. Setup `waldur.mastermindTemplating.mastermindTemplatesPath`
    in values.yaml (by default, it is equal to `mastermind_templates`)

1. Put all the custom template files in the mentioned directory
    with respect to their placement in the source code repository.
    For example, if you want to replace default `waldur_core/users/templates/users/invitation_approved_message.html`,
    you should put custom `invitation_approved_message.html`
    file into `<mastermindTemplatesPath>/waldur_core/users/templates/users/` directory.
    Hence, the custom template will present in
    `<mastermindTemplatesPath>/waldur_core/users/templates/users/invitation_approved_message.html`
    file.
